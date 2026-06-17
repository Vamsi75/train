# Lab Setup — OpenSSL CA + FreeRADIUS + Test Supplicant

A self-contained lab to reproduce everything in this guide: a 2-tier PKI, a
FreeRADIUS server doing EAP-TLS/PEAP, and a software supplicant to drive
authentications. Everything runs locally — no cloud, no real AD.

> Platform note: commands assume a POSIX shell (Linux / macOS / **WSL2 on
> Windows**). On Windows, install WSL2 (`wsl --install`) and run the lab inside
> the Linux distro. Docker Desktop with the WSL2 backend works fine.

---

## 0. Prerequisites

```bash
# Debian/Ubuntu (or WSL2 Ubuntu)
sudo apt update
sudo apt install -y openssl docker.io wireshark freeradius freeradius-utils wpasupplicant
sudo usermod -aG docker "$USER"   # log out/in (or 'newgrp docker') so docker works rootless
```

| Tool                | Why                                                    |
|---------------------|--------------------------------------------------------|
| OpenSSL ≥ 1.1.1     | Build the CA, issue certs, inspect, `s_client` testing |
| Docker              | Run FreeRADIUS without polluting the host              |
| Wireshark / tshark  | Watch EAPOL, EAP, RADIUS, TLS handshakes on the wire   |
| FreeRADIUS utils    | `radtest`, `radclient`, `radiusd -X`                   |
| wpa_supplicant      | `eapol_test` — the gold-standard EAP test driver       |

```bash
openssl version            # expect 1.1.1+ or 3.x
docker --version
eapol_test -h 2>&1 | head  # confirms wpa_supplicant built with eapol_test
```

Create the lab root:

```bash
export LAB=~/pki-lab
mkdir -p "$LAB" && cd "$LAB"
```

---

## 1. Build a 2-Tier CA with OpenSSL

Architecture: **offline Root CA** → signs one **Intermediate (Issuing) CA** →
the intermediate signs leaf certs (a RADIUS *serverAuth* cert and a user
*clientAuth* cert). This mirrors real deployments where the root is kept
air-gapped and only the intermediate signs day-to-day.

### 1.1 Directory layout

```bash
cd "$LAB"
mkdir -p root/{certs,crl,newcerts,private,csr}
mkdir -p intermediate/{certs,crl,newcerts,private,csr}
chmod 700 root/private intermediate/private
touch root/index.txt intermediate/index.txt
echo 1000 > root/serial
echo 1000 > intermediate/serial
echo 1000 > root/crlnumber
echo 1000 > intermediate/crlnumber
```

### 1.2 Root `openssl.cnf`

```bash
cat > root/openssl.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./root
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca.key.pem
certificate       = $dir/certs/ca.cert.pem
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days   = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 7300
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
organizationName        = match
commonName              = supplied

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
organizationName                = Organization Name
commonName                      = Common Name

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ crl_ext ]
authorityKeyIdentifier=keyid:always
EOF
```

### 1.3 Generate the Root key + self-signed Root cert

```bash
cd "$LAB"
# Root private key (encrypted; pick a passphrase you remember for the lab)
openssl genrsa -aes256 -out root/private/ca.key.pem 4096
chmod 400 root/private/ca.key.pem

# Self-signed root certificate (20 years), CA:true
openssl req -config root/openssl.cnf -key root/private/ca.key.pem \
  -new -x509 -days 7300 -sha256 -extensions v3_ca \
  -subj "/C=US/O=Lab PKI/CN=Lab Root CA" \
  -out root/certs/ca.cert.pem

openssl x509 -noout -text -in root/certs/ca.cert.pem | head -20
```

### 1.4 Intermediate `openssl.cnf`

Reuse the root config but point `dir` at the intermediate tree:

```bash
sed 's#dir *= ./root#dir = ./intermediate#' root/openssl.cnf > intermediate/openssl.cnf
# Add leaf-cert extension profiles the intermediate will use to sign:
cat >> intermediate/openssl.cnf <<'EOF'

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always

[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF
```

### 1.5 Intermediate key, CSR, and signing by the Root

```bash
cd "$LAB"
openssl genrsa -aes256 -out intermediate/private/intermediate.key.pem 4096
chmod 400 intermediate/private/intermediate.key.pem

# CSR for the intermediate
openssl req -config intermediate/openssl.cnf -new -sha256 \
  -key intermediate/private/intermediate.key.pem \
  -subj "/C=US/O=Lab PKI/CN=Lab Intermediate CA" \
  -out intermediate/csr/intermediate.csr.pem

# Root signs the intermediate (pathlen:0 — cannot create further sub-CAs)
openssl ca -config root/openssl.cnf -extensions v3_intermediate_ca \
  -days 3650 -notext -md sha256 -batch \
  -in intermediate/csr/intermediate.csr.pem \
  -out intermediate/certs/intermediate.cert.pem
chmod 444 intermediate/certs/intermediate.cert.pem

# Verify the intermediate chains to the root
openssl verify -CAfile root/certs/ca.cert.pem intermediate/certs/intermediate.cert.pem

# Build the CA chain file (intermediate + root) used by servers/supplicants
cat intermediate/certs/intermediate.cert.pem root/certs/ca.cert.pem \
  > intermediate/certs/ca-chain.cert.pem
```

### 1.6 RADIUS server cert (serverAuth) — with SAN

EAP-TLS/PEAP servers should carry the FQDN in a SAN and have EKU `serverAuth`.

```bash
cd "$LAB"
openssl genrsa -out intermediate/private/radius.key.pem 2048   # leaf, unencrypted for the daemon

openssl req -config intermediate/openssl.cnf -new -sha256 \
  -key intermediate/private/radius.key.pem \
  -subj "/C=US/O=Lab PKI/CN=radius.lab.local" \
  -addext "subjectAltName=DNS:radius.lab.local" \
  -out intermediate/csr/radius.csr.pem

openssl ca -config intermediate/openssl.cnf -extensions server_cert \
  -days 825 -notext -md sha256 -batch \
  -in intermediate/csr/radius.csr.pem \
  -out intermediate/certs/radius.cert.pem

openssl x509 -noout -text -in intermediate/certs/radius.cert.pem \
  | grep -A1 -E "Extended Key Usage|Subject Alternative"
```

### 1.7 User cert (clientAuth) — with UPN SAN

For EAP-TLS, Windows/NPS map the cert to an account via the **UPN** in the SAN
(`otherName` OID `1.3.6.1.4.1.311.20.2.3`). OpenSSL needs that encoded explicitly.

```bash
cd "$LAB"
openssl genrsa -out intermediate/private/user.key.pem 2048

# Build a SAN with the UPN otherName. The value is a UTF8String.
openssl req -config intermediate/openssl.cnf -new -sha256 \
  -key intermediate/private/user.key.pem \
  -subj "/C=US/O=Lab PKI/CN=alice" \
  -addext "subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:alice@lab.local" \
  -out intermediate/csr/user.csr.pem

openssl ca -config intermediate/openssl.cnf -extensions usr_cert \
  -days 365 -notext -md sha256 -batch \
  -in intermediate/csr/user.csr.pem \
  -out intermediate/certs/user.cert.pem

# Confirm the UPN landed in the SAN
openssl x509 -noout -text -in intermediate/certs/user.cert.pem \
  | grep -A2 "Subject Alternative Name"

# Bundle the user identity as a PFX for importing into a supplicant/OS
openssl pkcs12 -export -out intermediate/certs/alice.p12 \
  -inkey intermediate/private/user.key.pem \
  -in intermediate/certs/user.cert.pem \
  -certfile intermediate/certs/ca-chain.cert.pem \
  -passout pass:labpass
```

---

## 2. Run FreeRADIUS in Docker

We mount the lab certs into the container and point EAP at them.

```bash
cd "$LAB"
mkdir -p fr/certs fr/conf
# Copy the certs the server needs (chain + server leaf + server key)
cp intermediate/certs/ca-chain.cert.pem fr/certs/ca.pem
cp intermediate/certs/radius.cert.pem   fr/certs/server.pem
cp intermediate/private/radius.key.pem  fr/certs/server.key
```

### 2.1 Where config lives

The `freeradius/freeradius-server` image keeps config under
`/etc/raddb` (aka `/etc/freeradius`):

| File / dir                         | Purpose                                          |
|------------------------------------|--------------------------------------------------|
| `clients.conf`                     | NAS clients (IP + shared secret)                 |
| `mods-available/eap`               | EAP config: default method, TLS cert paths       |
| `mods-enabled/`                    | Symlinks to enabled modules (`eap`, `pap`, ...)  |
| `mods-config/files/authorize`      | The "users" file — static users/checks/replies   |
| `sites-enabled/default`, `inner-tunnel` | Virtual servers / policy flow              |

### 2.2 Minimal client (NAS)

```bash
cat > fr/conf/clients.conf <<'EOF'
client lab-nas {
    ipaddr = 0.0.0.0/0          # lab only — accept from anywhere
    secret = testing123
    require_message_authenticator = yes
    nas_type = other
}
EOF
```

### 2.3 Point EAP at the lab certs

```bash
cat > fr/conf/eap <<'EOF'
eap {
    default_eap_type = tls
    timer_expire     = 60
    type = tls
    type = peap
    type = ttls
    type = mschapv2

    tls-config tls-common {
        private_key_file = /etc/raddb/certs/server.key
        certificate_file = /etc/raddb/certs/server.pem
        ca_file          = /etc/raddb/certs/ca.pem
        # private_key_password = ...   # only if the key is encrypted
        dh_file          = /etc/raddb/certs/dh
        cipher_list      = "DEFAULT@SECLEVEL=1"
        tls_min_version  = "1.2"
        tls_max_version  = "1.2"
    }
    tls   { tls = tls-common }
    peap  { tls = tls-common  default_eap_type = mschapv2  virtual_server = "inner-tunnel" }
    ttls  { tls = tls-common  default_eap_type = mschapv2  virtual_server = "inner-tunnel" }
    mschapv2 { }
}
EOF
```

### 2.4 A test user (for PEAP/TTLS inner password auth)

```bash
cat > fr/conf/authorize <<'EOF'
bob   Cleartext-Password := "bobpass"
      Reply-Message := "Lab PEAP OK"
EOF
```

### 2.5 Start the container

```bash
cd "$LAB"
docker run -d --name fr \
  -p 1812-1813:1812-1813/udp \
  -v "$PWD/fr/certs:/etc/raddb/certs:ro" \
  -v "$PWD/fr/conf/clients.conf:/etc/raddb/clients.conf:ro" \
  -v "$PWD/fr/conf/eap:/etc/raddb/mods-available/eap:ro" \
  -v "$PWD/fr/conf/authorize:/etc/raddb/mods-config/files/authorize:ro" \
  freeradius/freeradius-server:latest

# Generate the DH params the container expects (one-time)
docker exec fr sh -c 'openssl dhparam -out /etc/raddb/certs/dh 2048'
docker restart fr

# Tail logs / confirm it's listening
docker logs -f fr
```

Run it in the foreground in debug mode whenever you need to see EAP internals
(see §4).

---

## 3. Test with `eapol_test` (wpa_supplicant)

`eapol_test` speaks the full EAP state machine straight to the RADIUS server —
no AP needed.

### 3.1 EAP-TLS config

```bash
cd "$LAB"
cat > eaptls.conf <<'EOF'
network={
    ssid="lab"
    key_mgmt=WPA-EAP
    eap=TLS
    identity="alice@lab.local"
    ca_cert="intermediate/certs/ca-chain.cert.pem"
    client_cert="intermediate/certs/user.cert.pem"
    private_key="intermediate/private/user.key.pem"
    # private_key_passwd="..."   # if the key were encrypted
}
EOF

eapol_test -c eaptls.conf -a 127.0.0.1 -s testing123 -r0
```

### 3.2 PEAP-MSCHAPv2 config

```bash
cd "$LAB"
cat > peap.conf <<'EOF'
network={
    ssid="lab"
    key_mgmt=WPA-EAP
    eap=PEAP
    identity="bob"
    anonymous_identity="anonymous"
    password="bobpass"
    ca_cert="intermediate/certs/ca-chain.cert.pem"
    phase2="auth=MSCHAPV2"
}
EOF

eapol_test -c peap.conf -a 127.0.0.1 -s testing123 -r0
```

### 3.3 Reading the result

- `-a` = RADIUS server IP, `-s` = shared secret, `-r0` = stop after one auth.
- Success ends with **`SUCCESS`** and an `Access-Accept`. You'll see the EAP
  method negotiated, the TLS handshake, and (for TLS) the cert chain validated.
- Failure prints `FAILURE` / `Access-Reject`. Common causes: wrong shared
  secret (server "ignoring" packet), CA mismatch (TLS alert `unknown_ca`),
  expired/clientAuth-missing cert, or identity not in `authorize`.

---

## 4. radtest / radclient / debug mode

```bash
# Foreground debug — the single most useful FreeRADIUS troubleshooting tool
docker stop fr
docker run --rm -it --name frx \
  -p 1812-1813:1812-1813/udp \
  -v "$PWD/fr/certs:/etc/raddb/certs:ro" \
  -v "$PWD/fr/conf/clients.conf:/etc/raddb/clients.conf:ro" \
  -v "$PWD/fr/conf/eap:/etc/raddb/mods-available/eap:ro" \
  -v "$PWD/fr/conf/authorize:/etc/raddb/mods-config/files/authorize:ro" \
  freeradius/freeradius-server:latest radiusd -X     # -X = full debug to stdout

# Simple PAP test against the 'bob' user (run from host with freeradius-utils)
radtest bob bobpass 127.0.0.1 0 testing123
#        user pass    server   nas-port secret  -> expect "Access-Accept"

# radclient: craft arbitrary requests, e.g. Status-Server health check
echo "Message-Authenticator = 0x00" | radclient -x 127.0.0.1:1812 status testing123

# Accounting start packet
echo "User-Name=bob,Acct-Status-Type=Start,Acct-Session-Id=abc123" \
  | radclient -x 127.0.0.1:1813 acct testing123
```

In `-X` output, look for: `Listening on auth ...`, the matched `client`,
`(N) eap: ...` lines showing method negotiation, TLS `--> verify return:1` for
each chain cert, and the final `Sent Access-Accept` / `Access-Reject`.

---

## 5. Wireshark / tshark filters

Capture on `lo`/`loopback` for the Docker lab (or the wireless interface for a
real AP). Decode UDP 1812/1813 as RADIUS if needed (Analyze → Decode As).

| Filter                         | Shows                                              |
|--------------------------------|----------------------------------------------------|
| `eapol`                        | 802.1X EAPOL frames (Start, the EAP exchange, key) |
| `eap`                          | EAP request/response, method type, Identity        |
| `radius`                       | Access-Request/Challenge/Accept/Reject, attributes |
| `radius.code == 11`            | Access-Challenge only (the EAP back-and-forth)     |
| `tls.handshake`                | TLS within EAP-TLS/PEAP/TTLS tunnel                |
| `tls.handshake.type == 1`      | ClientHello (offered ciphers/versions/SNI)         |
| `tls.handshake.type == 11`     | Certificate message (server/client chain)          |
| `tls.alert_message`            | TLS alerts — `unknown_ca`, `certificate_expired`   |

What to look for:
- **EAP-Identity** response reveals the outer identity (privacy = anonymous).
- In **Access-Challenge** loops, the `EAP-Message` attributes carry TLS records
  fragmented across packets — Wireshark reassembles them.
- A **certificate_unknown / unknown_ca** alert means the peer doesn't trust the
  other side's chain — fix `ca_file` / `ca_cert`.
- `Access-Reject` with no TLS = shared-secret or message-authenticator problem.

```bash
# Headless capture of the RADIUS conversation
sudo tshark -i lo -f "udp port 1812 or udp port 1813" -Y radius
```

---

## Teardown / cleanup

```bash
docker rm -f fr frx 2>/dev/null
docker rmi freeradius/freeradius-server:latest 2>/dev/null
rm -rf ~/pki-lab            # nukes the entire CA + configs + test files
```

> The Root CA key in this lab is on disk and unprotected by HSM — fine for a
> throwaway lab, never for production. In the real world the root is offline,
> the intermediate signs, and keys live in an HSM/TPM.
