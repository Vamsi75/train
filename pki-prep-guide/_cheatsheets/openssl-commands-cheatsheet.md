# OpenSSL / Cert / RADIUS Command Cheatsheet

Dense, copy-pasteable reference. Grouped by task. OpenSSL 1.1.1 / 3.x syntax.

---

### Generate keys (RSA / EC)

```bash
openssl genrsa -out key.pem 2048                                  # RSA 2048 private key
openssl genrsa -aes256 -out key.pem 4096                          # RSA 4096, encrypted with passphrase
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out key.pem  # modern RSA gen
openssl ecparam -name prime256v1 -genkey -noout -out ec.key       # EC P-256 (prime256v1)
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out ec.key # EC P-384 via genpkey
openssl genpkey -algorithm ed25519 -out ed.key                    # Ed25519 key
openssl rsa -in key.pem -pubout -out pub.pem                      # extract public key from private
openssl pkey -in key.pem -text -noout                             # inspect any private key
```

### Create CSR (with SAN)

```bash
openssl req -new -key key.pem -out req.csr -subj "/C=US/O=Org/CN=host.example.com"  # basic CSR
openssl req -new -key key.pem -out req.csr \
  -addext "subjectAltName=DNS:host.example.com,DNS:www.example.com"                 # CSR w/ DNS SAN (1.1.1+)
openssl req -new -key key.pem -out req.csr \
  -addext "subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:user@example.com"   # UPN SAN (EAP-TLS user)
openssl req -newkey rsa:2048 -nodes -keyout key.pem -out req.csr -subj "/CN=host"   # gen key + CSR together
```

### Self-sign / sign with a CA

```bash
openssl req -x509 -new -key key.pem -days 3650 -sha256 -out ca.crt -subj "/CN=Test Root"   # self-signed CA/cert
openssl x509 -req -in req.csr -signkey key.pem -days 365 -out self.crt                      # self-sign a CSR
openssl x509 -req -in req.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 \
  -extfile <(printf "subjectAltName=DNS:host.example.com\nextendedKeyUsage=serverAuth") \
  -out host.crt                                                                             # sign w/ CA + SAN/EKU
openssl ca -config openssl.cnf -extensions server_cert -in req.csr -out host.crt -batch     # sign via 'ca' DB
```

### Inspect

```bash
openssl x509 -in cert.pem -noout -text                            # full human-readable certificate
openssl x509 -in cert.pem -noout -subject -issuer -dates -serial  # quick fields
openssl x509 -in cert.pem -noout -ext subjectAltName              # just the SAN
openssl req  -in req.csr   -noout -text -verify                   # decode CSR + verify its signature
openssl crl  -in crl.pem   -noout -text                           # decode a CRL
openssl asn1parse -in cert.pem                                    # raw ASN.1 structure
openssl pkcs7 -in chain.p7b -inform DER -print_certs -noout       # list certs inside a PKCS#7
```

### Verify chains

```bash
openssl verify -CAfile root.pem cert.pem                          # verify cert against a root
openssl verify -CAfile root.pem -untrusted intermediate.pem cert.pem   # with intermediate(s)
openssl verify -CAfile root.pem -purpose sslserver cert.pem       # enforce EKU/purpose
openssl s_client -connect host:443 -showcerts                     # dump the chain a server presents
openssl s_client -connect host:443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer                          # subject/issuer of the leaf
openssl verify -verbose -CAfile root.pem cert.pem                 # verbose failure reasons
```

### Convert formats (PEM / DER / PKCS12 / PKCS7 / PKCS8)

```bash
openssl x509 -in cert.pem -outform DER -out cert.der              # PEM -> DER
openssl x509 -in cert.der -inform DER -out cert.pem               # DER -> PEM
openssl pkcs12 -export -in cert.pem -inkey key.pem -certfile chain.pem -out bundle.p12  # PEM -> PFX/P12
openssl pkcs12 -in bundle.p12 -nodes -out all.pem                 # PFX -> PEM (key+certs, no encryption)
openssl crl2pkcs7 -nocrl -certfile chain.pem -out chain.p7b       # PEM -> PKCS#7
openssl pkcs7 -in chain.p7b -print_certs -out chain.pem           # PKCS#7 -> PEM
openssl pkcs8 -topk8 -in trad.key -out pkcs8.key -nocrypt         # traditional key -> PKCS#8
openssl rsa -in pkcs8.key -out trad.key                           # PKCS#8 -> traditional RSA
```

### Check expiry

```bash
openssl x509 -in cert.pem -noout -enddate                         # notAfter date
openssl x509 -in cert.pem -noout -checkend 0                      # exit 0 if NOT expired now
openssl x509 -in cert.pem -noout -checkend 2592000                # expires within 30 days? (nonzero exit)
openssl s_client -connect host:443 </dev/null 2>/dev/null \
  | openssl x509 -noout -dates                                    # remote cert validity dates
```

### Extract from PFX / PKCS12

```bash
openssl pkcs12 -in bundle.p12 -clcerts -nokeys -out cert.pem      # leaf cert only
openssl pkcs12 -in bundle.p12 -cacerts -nokeys -out cacerts.pem   # CA certs only
openssl pkcs12 -in bundle.p12 -nocerts -nodes -out key.pem        # private key only (unencrypted)
openssl pkcs12 -in bundle.p12 -info -noout                        # show MAC/encryption algorithms used
```

### Fingerprints & hashes

```bash
openssl x509 -in cert.pem -noout -fingerprint -sha256             # SHA-256 cert fingerprint
openssl x509 -in cert.pem -noout -fingerprint -sha1               # SHA-1 fingerprint (legacy)
openssl x509 -in cert.pem -noout -modulus | openssl md5           # cert modulus hash (match to key)
openssl rsa  -in key.pem  -noout -modulus | openssl md5           # key modulus hash (must match cert)
openssl x509 -in cert.pem -noout -pubkey | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary | openssl base64                 # SPKI pin (HPKP-style)
```

### CRL & OCSP

```bash
openssl ca -config openssl.cnf -gencrl -out crl.pem               # generate a CRL from the CA DB
openssl ca -config openssl.cnf -revoke bad.crt                    # revoke a cert (then regen CRL)
openssl crl -in crl.pem -noout -text                              # inspect CRL (revoked serials, next update)
openssl ocsp -issuer ca.crt -cert cert.pem -url http://ocsp.example.com -text  # OCSP query to responder
openssl ocsp -index index.txt -CA ca.crt -rsigner ocsp.crt -rkey ocsp.key -port 8888  # run a test responder
openssl s_client -connect host:443 -status </dev/null             # request OCSP stapling from server
```

### TLS test (s_client / s_server)

```bash
openssl s_client -connect host:443                                # open a TLS connection, show details
openssl s_client -connect host:443 -servername host -showcerts    # SNI + full chain
openssl s_client -connect host:443 -tls1_2                        # force TLS 1.2
openssl s_client -connect host:443 -tls1_3                        # force TLS 1.3
openssl s_client -connect host:443 -cipher 'ECDHE-RSA-AES256-GCM-SHA384'  # force a cipher (TLS1.2)
openssl s_client -connect host:443 -ciphersuites TLS_AES_256_GCM_SHA384   # force TLS1.3 ciphersuite
openssl s_client -connect host:636 -starttls ldap                 # STARTTLS (smtp/imap/ldap/...)
openssl s_server -accept 4433 -cert cert.pem -key key.pem -www    # quick test TLS server
openssl ciphers -v 'HIGH:!aNULL'                                  # list ciphers matching a spec
```

### keytool (Java) basics

```bash
keytool -genkeypair -alias me -keyalg RSA -keysize 2048 -keystore ks.jks   # gen key in JKS
keytool -list -v -keystore ks.jks                                          # list keystore contents
keytool -importcert -alias root -file ca.crt -keystore truststore.jks      # import a trusted CA
keytool -certreq -alias me -file me.csr -keystore ks.jks                   # generate CSR
keytool -importcert -alias me -file signed.crt -keystore ks.jks            # import signed reply
keytool -importkeystore -srckeystore b.p12 -srcstoretype PKCS12 -destkeystore ks.jks  # PFX -> JKS
keytool -printcert -file cert.crt                                          # inspect a cert file
```

### certutil (Windows) basics

```powershell
certutil -dump cert.cer                                           # decode/inspect a certificate
certutil -verify -urlfetch cert.cer                               # validate chain + CRL/OCSP fetch
certutil -addstore -f Root ca.cer                                 # add CA to LocalMachine Root store
certutil -store My                                                # list certs in personal (My) store
certutil -hashfile file.bin SHA256                                # SHA-256 of a file
certutil -p pass -importpfx bundle.pfx                            # import a PFX into the store
certutil -crl                                                     # publish CRLs (on a CA)
```

### FreeRADIUS commands

```bash
radiusd -X                                                        # run server in full foreground debug
radiusd -XC                                                       # check config & exit (no run)
radtest bob bobpass 127.0.0.1 0 testing123                        # PAP test: user pass server port secret
radtest -t mschap bob bobpass 127.0.0.1 0 testing123              # MSCHAP test
echo "User-Name=bob,User-Password=bobpass" | radclient -x 127.0.0.1 auth testing123  # auth via radclient
echo "Message-Authenticator=0x00" | radclient -x host:1812 status testing123          # Status-Server probe
eapol_test -c eaptls.conf -a 127.0.0.1 -s testing123 -r0          # drive EAP (EAP-TLS/PEAP) to RADIUS
eapol_test -c peap.conf -a 127.0.0.1 -s testing123 -N 30:s:wifi   # add a custom RADIUS attr
```
