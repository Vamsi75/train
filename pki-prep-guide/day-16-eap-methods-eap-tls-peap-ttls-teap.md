# Day 16 — EAP Methods: EAP-TLS, PEAP, EAP-TTLS, TEAP

> "The wire is hostile. EAP decides whether the only secret that ever touches that wire is a cryptographic proof you already hold — or a password an attacker can phish in 90 seconds." This is the heart of SecureW2's passwordless thesis.

---

## THEORY

EAP (Extensible Authentication Protocol, RFC 3748) is **not an authentication method** — it is a *framework* that carries authentication conversations. 802.1X uses EAP to negotiate a method between the **supplicant** (client), the **authenticator** (switch/AP/WLC), and the **authentication server** (RADIUS). The authenticator is a dumb pass-through: it tunnels EAP inside `EAPOL` (EAP over LAN) on the wire and re-encapsulates it inside RADIUS `Access-Request` attributes (`EAP-Message`) toward the server. **The method matters enormously** — it determines whether credentials are phishable, whether you need PKI, and whether auth is mutual.

### 1. The EAP conversation skeleton (every method)

```text
Supplicant            Authenticator(AP/Switch)            RADIUS Server
   |  EAPOL-Start ------->  |                                  |
   |  <---- EAP-Request/Identity                               |
   |  EAP-Response/Identity (anonymous@realm) -->  RADIUS Access-Request
   |                        |  ---------------------------->   |
   |  <==================  EAP method exchange  ============>  |  (multiple round trips)
   |                        |  <---------------------------    |
   |  <---- EAP-Success  <-- RADIUS Access-Accept (+ MSK in MPPE keys, VLAN, etc.)
```

Key facts:
- The **outer identity** in `EAP-Response/Identity` is often anonymous (`anonymous@example.com`) for tunneled methods — the *real* identity is protected inside the TLS tunnel. This is "identity privacy."
- On `Access-Accept`, the RADIUS server ships the **MSK (Master Session Key)** to the authenticator inside `MS-MPPE-Recv-Key` / `MS-MPPE-Send-Key` (encrypted with the RADIUS shared secret). That MSK seeds the WPA 4-way handshake (Day 17). **No keying material = no Wi-Fi**, even after EAP-Success.

### 2. EAP-TLS (RFC 5216) — the gold standard

EAP-TLS runs a **full mutual TLS handshake inside EAP**. Both sides present X.509 certificates.

```text
Supplicant                                  RADIUS (EAP server)
  EAP-Response: TLS ClientHello ----------->
  <--------- ServerHello, Server Certificate, CertificateRequest, ServerHelloDone
  Client Certificate, ClientKeyExchange,
  CertificateVerify, ChangeCipherSpec, Finished -->
  <--------- ChangeCipherSpec, Finished
  (TLS established; keys exported per RFC 5216) 
  <--------- EAP-Success
```

Why it is the gold standard:
- **Mutual authentication.** Server proves identity to client (validated against a trusted root + expected name); client proves identity with its own cert and **proof of possession of the private key** (`CertificateVerify` is signed by the client private key). An attacker who steals the public cert cannot authenticate.
- **No password ever on the wire.** There is no shared secret to phish, replay, or crack offline. Credential-theft attacks (rogue AP, evil twin) collapse — there's nothing to steal.
- **Keying material is derived from the TLS master secret** via the EAP-TLS PRF/exporter — strong, per-session, forward-secret with TLS 1.3.
- **Phishing-resistant.** This is *the* reason SecureW2 builds its entire platform (managed PKI, JoinNow onboarding, Cloud RADIUS) around EAP-TLS: you eliminate the password as an attack surface.

Cost / gotchas:
- **Requires PKI.** Every client needs a certificate enrolled (SCEP/EST/ACME or onboarding tooling). This is the historical adoption barrier — and exactly the problem SecureW2's managed PKI + onboarding solves.
- Client cert lifecycle (enrollment, renewal, revocation via CRL/OCSP) must be operationalized. A dead/revoked cert = no network.
- TLS 1.3 in EAP-TLS is RFC 9190 (EAP-TLS 1.3); it changes the exporter labels and removes the legacy `EAP-TLS` PRF — make sure server + supplicant agree.

### 3. PEAP (Protected EAP) — server-cert tunnel, password inside

PEAP (Microsoft/Cisco/RSA, no single clean RFC — `draft-josefsson-pppext-eap-tls-eap`) does a **server-side-only** TLS handshake to build a tunnel, then runs a **second, inner EAP method** inside it — almost always **EAP-MSCHAPv2**.

```text
Phase 1 (outer): TLS tunnel using SERVER cert only (no client cert)
Phase 2 (inner): EAP-MSCHAPv2  (username + MSCHAPv2 challenge/response)
                 protected by the Phase-1 tunnel
```

- **Only the server needs a certificate.** No client PKI — this is why PEAP-MSCHAPv2 dominated AD environments: domain username/password "just works."
- The inner MSCHAPv2 exchange is protected by the tunnel, so it's safe **only if the tunnel terminated at the legitimate server**.

The vulnerabilities (know these cold):
- **MSCHAPv2 is cryptographically broken.** It uses DES-based challenge/response over the NT hash. Tools like `asleap` / `chapcrack` reduce the MSCHAPv2 handshake to a single DES key recovery (effectively 2^56, practically cracked via cloud/`crack.sh`). If an attacker captures an *unprotected* MSCHAPv2 exchange, they recover the NT hash → the password.
- **Evil-twin / rogue RADIUS.** If the client **does not validate the server certificate** (untrusted root, or "don't validate" checked, or no server-name check), an attacker stands up a fake SSID + fake RADIUS (e.g. `hostapd-wpe` / `eaptls-mitm`), the client cheerfully builds the tunnel **to the attacker**, and then hands over the MSCHAPv2 exchange — which the attacker decrypts and cracks. This is the **#1 real-world 802.1X compromise**.
- **Therefore the entire security of PEAP rests on correct server-certificate validation on every client** — a configuration item, not a protocol guarantee. That is fragile at scale.

### 4. EAP-TTLS (RFC 5281) — tunnel + flexible inner

EAP-TTLS also builds a **server-cert TLS tunnel**, but inside it carries **AVPs** (RADIUS-style attribute-value pairs) supporting a wider set of inner methods: **PAP, CHAP, MS-CHAP, MS-CHAPv2, or inner EAP**.

- The big differentiator: **inner PAP.** PAP sends the cleartext password *inside the encrypted tunnel*, which lets the RADIUS server perform a **backend bind/lookup** against AD, LDAP, a SQL DB, or an **OTP/token** system — because the server actually sees the cleartext credential to verify it. PEAP-MSCHAPv2 cannot do this (it needs the NT hash, not arbitrary backends).
- Same fatal dependency as PEAP: **security collapses if the client doesn't validate the server cert.** Inner PAP is *cleartext password* — if the tunnel terminates at an attacker, the password is handed over directly. Validation is non-negotiable.

### 5. TEAP (RFC 7170) — tunneled EAP with EAP chaining

TEAP (Tunnel EAP) is the modern IETF-standard tunneled method. Server-cert TLS tunnel, then inner method(s) carried as **TLVs**.

Its headline feature is **EAP chaining**: authenticate **machine AND user in a single EAP conversation**, returning a combined result. This answers a real enterprise need — "only allow user X *on a corporate-managed machine*." Windows native supplicant supports TEAP (machine + user chaining).

- TEAP also defines **provisioning** (it can deliver a trusted root / even a client cert as a PAC-like TLV during the tunnel), enabling smoother onboarding.
- Considered the successor to PEAP/EAP-FAST for password/hybrid scenarios. Still: **validate the server cert.**

### 6. EAP-FAST (RFC 4851) — briefly, the PAC method

Cisco's EAP-FAST builds the tunnel from a **PAC (Protected Access Credential)** — a shared secret provisioned to the client (anonymous or authenticated in-band provisioning) instead of (or alongside) a server cert. Solves "no PKI" tunnel bootstrapping. **Risk:** anonymous PAC provisioning (Phase 0) is MITM-able. Largely superseded by TEAP.

### 7. Comparison table

| Property | EAP-TLS | PEAP-MSCHAPv2 | EAP-TTLS (PAP) | TEAP | EAP-FAST |
|---|---|---|---|---|---|
| Mutual auth | **Yes (cert↔cert)** | Server cert + inner pw | Server cert + inner pw | Server cert + inner | PAC / server cert |
| Password on wire | **None** | Hashed (MSCHAPv2) in tunnel | Cleartext **in tunnel** | In tunnel | In tunnel |
| Client PKI needed | **Yes** | No | No | No (optional) | No (PAC) |
| Server PKI needed | Yes | Yes | Yes | Yes | Optional (PAC) |
| Phishable / evil-twin | **No** | **Yes** if cert not validated | **Yes** if cert not validated | Yes if cert not validated | Yes (PAC prov) |
| Backend AD/LDAP/OTP lookup | N/A (cert) | NT-hash only | **Yes (PAP)** | Yes | Yes |
| EAP chaining (machine+user) | No (per-conn) | No | No | **Yes** | Limited |
| Verdict | **Use this** | Legacy / migrate off | Niche (OTP/LDAP) | Modern alt to PEAP | Legacy |

### 8. The bottom line — go passwordless

Every tunneled method (PEAP/TTLS/TEAP/FAST) has the **same single point of failure**: a human-managed "validate the server certificate" checkbox. Get it wrong on one device fleet and you've shipped a credential-harvesting honeypot to your attacker. EAP-TLS removes the password entirely — there is *nothing to harvest*. With managed PKI + Cloud RADIUS (SecureW2's model), the historical "PKI is hard" objection disappears, and you get phishing-resistant, MFA-equivalent network access. **If you take one thing from Day 16: deploy EAP-TLS.**

### 9. The #1 misconfiguration (memorize)

Clients **must** be configured to:
1. **Validate the server certificate** (don't disable, don't "accept any").
2. Trust a **specific, named root/intermediate CA** — not the OS default public trust store (otherwise a Let's Encrypt cert on a rogue RADIUS would pass).
3. Pin the **expected RADIUS server name(s)** (CN/SAN), e.g. `radius.example.com`.

Miss any one of these and tunneled EAP is wide open to evil-twin credential theft. EAP-TLS sidesteps the consequence but you still validate the server cert there too.

---

## PRACTICE

### FreeRADIUS — `mods-available/eap` (TLS + PEAP)

```text
# /etc/freeradius/3.0/mods-available/eap
eap {
    default_eap_type = tls        # prefer EAP-TLS as the default offered method

    timer_expire   = 60
    ignore_unknown_eap_types = no
    cisco_accounting_username_bug = no
    max_sessions = ${max_requests}

    # ---- TLS server certificate / CA config shared by tls/peap/ttls ----
    tls-config tls-common {
        private_key_password = whatever
        private_key_file = /etc/freeradius/3.0/certs/server.key
        certificate_file = /etc/freeradius/3.0/certs/server.pem   # RADIUS server cert (CN=radius.example.com)
        ca_file          = /etc/freeradius/3.0/certs/ca.pem       # CA that signs CLIENT certs (for EAP-TLS)

        # Force modern TLS
        tls_min_version = "1.2"
        tls_max_version = "1.3"

        # Client cert revocation checking (EAP-TLS)
        check_crl = yes
        # ocsp { enable = yes  override_cert_url = yes  url = "http://ocsp.example.com/" }

        cipher_list = "HIGH:!aNULL:!eNULL"
        ecdh_curve = "prime256v1"
    }

    # ---- EAP-TLS: certificate-based mutual auth ----
    tls {
        tls = tls-common
        # Pin which client cert fields are acceptable / map to identity:
        # virtual_server = check-eap-tls   # (advanced: enforce SAN/UPN policy, AD lookup of cert)
    }

    # ---- PEAP: server-cert tunnel, inner MSCHAPv2 ----
    peap {
        tls = tls-common
        default_eap_type = mschapv2     # inner method
        copy_request_to_tunnel = no
        use_tunneled_reply = yes
        virtual_server = "inner-tunnel"
    }

    # ---- TTLS: server-cert tunnel, inner PAP/MSCHAPv2 ----
    ttls {
        tls = tls-common
        default_eap_type = mschapv2     # or 'pap' to enable AD/LDAP/OTP backend bind
        copy_request_to_tunnel = no
        use_tunneled_reply = yes
        virtual_server = "inner-tunnel"
    }

    mschapv2 { }
}
```

```text
# sites-enabled/inner-tunnel  (Phase-2 for PEAP/TTLS) — where AD/LDAP/OTP lookup happens
authorize {
    # ttls-PAP path: ldap   (bind cleartext pw to AD/LDAP)
    # peap-MSCHAPv2 path: ntlm_auth / mschap (needs NT hash from AD)
    eap { ok = return }
    mschap
    ldap
}
```

### Generate a client cert for EAP-TLS testing

```bash
# Sign a client cert off the test CA (real life: SCEP/EST/ACME via managed PKI)
openssl req -new -newkey rsa:2048 -nodes -keyout client.key \
  -subj "/CN=alice@example.com" -out client.csr
openssl x509 -req -in client.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 730 -out client.pem -extfile <(printf "subjectAltName=otherName:msUPN;UTF8:alice@example.com")
```

### Test EAP-TLS with `eapol_test` (wpa_supplicant tools)

```text
# eaptls.conf  — eapol_test EAP-TLS profile
network={
    ssid="EAP-TLS-TEST"
    key_mgmt=WPA-EAP
    eap=TLS
    identity="alice@example.com"
    ca_cert="/etc/freeradius/3.0/certs/ca.pem"   # trust the RADIUS server's CA
    client_cert="/path/client.pem"
    private_key="/path/client.key"
    # private_key_passwd="..."
    # CRITICAL: pin the expected server identity (anti evil-twin)
    altsubject_match="DNS:radius.example.com"
    # subject_match="/CN=radius.example.com"
}
```

```bash
# Run against the RADIUS server (shared secret 'testing123')
eapol_test -c eaptls.conf -a 127.0.0.1 -p 1812 -s testing123 -r0
# Expect: ... EAP-TLS ... SUCCESS  + "MPPE keys OK"  (MSK derived) at the end.
```

### Test PEAP-MSCHAPv2 with eapol_test (note the server-validation knobs)

```text
network={
    ssid="PEAP-TEST"
    key_mgmt=WPA-EAP
    eap=PEAP
    identity="alice"                         # inner identity
    anonymous_identity="anonymous@example.com"  # outer, in cleartext
    password="S3cret!"
    ca_cert="/etc/freeradius/3.0/certs/ca.pem"  # MUST be set — never omit in production
    altsubject_match="DNS:radius.example.com"   # MUST pin server name
    phase2="auth=MSCHAPV2"
}
```

### Supplicant profile settings that actually matter (any tunneled method)

```text
# Windows / wired-wireless XML profile or GPO equivalent:
ServerValidation.ServerNames     = radius.example.com   # pin SAN/CN
ServerValidation.TrustedRootCAs  = <thumbprint of YOUR CA>   # not "all public CAs"
ServerValidation.DisableUserPromptForServerValidation = true  # don't let users click "trust"
# macOS/iOS: deliver via .mobileconfig with PayloadCertificateAnchorUUID (pinned CA) + ServerCertificateNames
```

**Exercises:**
1. Stand up FreeRADIUS, enroll a client cert, and get a clean `SUCCESS` from `eapol_test` with EAP-TLS. Then revoke the cert (CRL) and confirm it now fails.
2. Run the PEAP profile **once with `ca_cert` set and `altsubject_match` set**, then again with both removed. Capture both with `tcpdump`/Wireshark and explain why the second one is exploitable by a rogue RADIUS.
3. Configure FreeRADIUS `inner-tunnel` to do **EAP-TTLS/PAP → LDAP bind** against a test OpenLDAP. Why can TTLS-PAP do this when PEAP-MSCHAPv2 cannot?
4. Build a `hostapd-wpe` rogue AP in a lab and demonstrate MSCHAPv2 challenge/response capture against a *misconfigured* client. Then show EAP-TLS yields nothing crackable.
5. Configure TEAP machine+user chaining on a Windows client and observe the combined result in the RADIUS logs.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. PEAP encrypts MSCHAPv2 inside a TLS tunnel, so how is it still phishable?**
The tunnel only protects the exchange *if it terminated at the real server*. Security is conditional on the **client validating the server certificate** (trusted CA + pinned name). If validation is off/misconfigured, the client builds the tunnel to a rogue RADIUS, which then sees the MSCHAPv2 challenge/response in the clear, and `asleap`/`crack.sh` recovers the NT hash → password. The crypto is fine; the trust anchor is the weak link. EAP-TLS has no such conditional secret.

**Q2. Both EAP-TLS and PEAP "use a server certificate." What's the real difference?**
PEAP uses the server cert **one-directionally** to build a tunnel; the client authenticates with a *password* inside. EAP-TLS uses certificates **bidirectionally** — the client also presents a cert and signs `CertificateVerify` with its private key (proof of possession). EAP-TLS therefore has **mutual cryptographic auth and zero password**; PEAP has server-auth + password.

**Q3. Why can EAP-TTLS authenticate against an OTP token or arbitrary LDAP, but PEAP-MSCHAPv2 cannot?**
TTLS supports **inner PAP**, which transmits the *cleartext* password inside the encrypted tunnel. The RADIUS server thus possesses the actual credential and can perform a backend **bind/verify** against anything (AD bind, LDAP, OTP validation API). MSCHAPv2 is a challenge/response over the **NT hash**, so the server needs the stored NT hash to verify it (via AD/`ntlm_auth`) — it can't drive an OTP or a system that doesn't expose NT hashes.

**Q4. What exactly does the RADIUS server send back on Access-Accept that makes Wi-Fi work, and why does EAP-Success alone not?**
EAP-Success only says "you're authenticated." The **MSK** (derived from the TLS master secret in TLS-based methods) is exported and delivered to the authenticator inside `MS-MPPE-Recv-Key`/`MS-MPPE-Send-Key` (encrypted under the RADIUS shared secret). The AP derives the **PMK** from the MSK and runs the WPA **4-way handshake** to install session keys. No MSK → no PMK → no encrypted data path, even with EAP-Success.

**Q5. A client trusts the cert because it chains to a public CA (e.g., Let's Encrypt). Why is that dangerous for PEAP?**
If the supplicant trusts *any* publicly-trusted CA rather than **your specific CA + your specific server name**, an attacker can put a perfectly valid public cert (for a domain they own) on a rogue RADIUS, pass validation, and harvest credentials. You must pin the **named CA** and the **server name (CN/SAN)**, not delegate trust to the public PKI.

**Q6. What is TEAP's EAP chaining and what problem does it solve that PEAP can't?**
TEAP runs **machine and user authentication in one EAP conversation** and returns a combined result, letting policy enforce "user allowed **only on a corporate-managed device**." PEAP authenticates a single identity per connection; correlating machine + user historically required fragile tricks (machine auth then user auth as separate sessions). TEAP makes the AND-condition native.

**Q7. Is EAP-FAST safe? When would you still see it?**
EAP-FAST tunnels off a **PAC** (shared secret) instead of requiring a server cert. Its weakness is **anonymous PAC provisioning (Phase 0)**, which is MITM-able. You see it in legacy Cisco shops. The modern answer is **TEAP** (or better, EAP-TLS).

**Q8. TLS 1.3 changed EAP-TLS. What should an engineer check?**
EAP-TLS 1.3 is **RFC 9190** — it uses TLS 1.3's exporter (`EXPORTER_EAP_TLS_Key_Material`), removes the legacy PRF, and adds a post-handshake `0x00` close. Both supplicant and server stacks must support it, or they'll fall back to TLS 1.2. Verify your FreeRADIUS (≥3.2/4.x) and supplicant (recent wpa_supplicant/OS) versions and that `tls_max_version = "1.3"` actually negotiates.

**Q9. "We can't do EAP-TLS, PKI is too hard." Rebut it.**
That objection predates managed PKI + onboarding. With a cloud CA, automated enrollment (SCEP/EST/ACME), self-service onboarding (e.g. SecureW2 JoinNow), and Cloud RADIUS, certs are issued and renewed automatically per device — no helpdesk password resets, no phishable secret, and you gain revocation-based instant deauthorization. The "hard PKI" cost is now lower than the *ongoing* cost of password resets, MSCHAPv2 breaches, and evil-twin exposure.

➡ Next: [Day 17 — WPA2/WPA3-Enterprise: The Full Wireless 802.1X Flow](day-17-wpa-enterprise-wireless-8021x-flow.md)
