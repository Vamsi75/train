# Day 04 — Encodings, Formats & the PKCS Family

## THEORY

### 1. The layer cake: structure, encoding, container

The single biggest source of "why won't this cert load" pain is that people conflate three independent layers. Keep them separate in your head:

| Layer | Question it answers | Examples |
|-------|---------------------|----------|
| **Abstract structure** | *What fields exist?* | X.509 Certificate, RSAPrivateKey, CertificationRequest — all defined in **ASN.1** |
| **Encoding** | *How are those fields turned into bytes?* | **DER** (binary), **BER**, **PEM** (base64 of DER + text headers) |
| **Container / bundle** | *What objects are packaged together, and is the bundle protected?* | PKCS#12 (.pfx), PKCS#7 (.p7b), a JKS keystore, a raw PEM file |

A `.pfx` is not "another kind of cert." It is a **container** that holds X.509 certs (structure) that were DER-encoded (encoding) and then wrapped, encrypted, and MAC'd. When you debug, always ask: *which layer is wrong?*

### 2. ASN.1 → DER → PEM

**ASN.1 (Abstract Syntax Notation One)** is the schema language. An X.509 cert in ASN.1 is a `SEQUENCE` of a `TBSCertificate`, a signature algorithm, and a signature `BIT STRING`. ASN.1 itself is abstract — it says nothing about bytes.

**DER (Distinguished Encoding Rules)** is the canonical binary serialization of ASN.1. "Distinguished" = exactly one valid byte representation for any given value (no optional whitespace, defined lengths only, sorted SET members). This determinism is *load-bearing*: signatures are computed over the DER bytes, so any ambiguity would break verification. DER is a TLV format — every element is **Tag, Length, Value**.

```
30 82 03 a1   # 0x30 = SEQUENCE, 0x82 = next 2 bytes are length, 0x03a1 = 929 bytes
   30 82 ...  # TBSCertificate (another SEQUENCE)
```

**PEM (Privacy-Enhanced Mail)** is just base64-encoded DER wrapped in ASCII armor:

```
-----BEGIN CERTIFICATE-----
MIIDoTCCAomgAwIBAgIU...   <- base64 of the DER bytes
-----END CERTIFICATE-----
```

Why PEM exists and dominates in practice:
- **Copy-paste safe** — survives email, web forms, YAML, env vars.
- **Concatenatable** — a PEM file can hold a leaf cert, then intermediate, then root, then a private key, stacked one after another. This is how nginx/Apache bundles, HAProxy PEMs, and many "fullchain.pem" files work.
- The `BEGIN`/`END` label tells the parser *what kind of object* the base64 is (`CERTIFICATE`, `RSA PRIVATE KEY`, `PRIVATE KEY`, `ENCRYPTED PRIVATE KEY`, `CERTIFICATE REQUEST`, `X509 CRL`, `PKCS7`).

> **Gotcha:** the label is advisory. A file labeled `BEGIN RSA PRIVATE KEY` is PKCS#1; `BEGIN PRIVATE KEY` is PKCS#8 (unencrypted); `BEGIN ENCRYPTED PRIVATE KEY` is PKCS#8 (encrypted). Tools that only handle one will silently reject the others.

### 3. File-extension chaos (and what's *actually* inside)

Extensions are a **convention, not a contract**. The bytes decide. This table is the truth:

| Extension | Usual encoding | Usually contains | Reality check |
|-----------|----------------|------------------|---------------|
| `.pem` | PEM | anything (cert, key, chain, CSR) | look at the BEGIN line |
| `.crt` / `.cer` | PEM **or** DER | a certificate | `.cer` on Windows is often DER; on Unix often PEM |
| `.der` | DER | a certificate or key | binary, won't open in a text editor |
| `.key` | PEM (usually) | a private key | may be PKCS#1 or PKCS#8, encrypted or not |
| `.csr` / `.req` | PEM/DER | a PKCS#10 CSR | |
| `.p7b` / `.p7c` | DER or PEM | PKCS#7 — **certs/chain only, NO private key** | great for shipping chains to Windows/IIS |
| `.pfx` / `.p12` | DER | PKCS#12 — cert + key + chain, password-protected | the all-in-one bundle |

**Rule of thumb:** if you don't know what a file is, run `openssl asn1parse` or `file`, or just `head` it — text with `-----BEGIN` is PEM, gibberish is DER/PKCS#12.

### 4. The PKCS family — memorize the numbers

PKCS = Public-Key Cryptography Standards (originally RSA Labs). The ones you must know cold:

| Standard | Purpose | BEGIN label / extension |
|----------|---------|-------------------------|
| **PKCS#1** | RSA key syntax (raw RSA public/private key) | `BEGIN RSA PRIVATE KEY` |
| **PKCS#7** | CMS — signed/enveloped data; in PKI, used to ship **cert chains** (no keys) | `BEGIN PKCS7`, `.p7b` |
| **PKCS#8** | Generic private-key container (any algorithm), optionally **encrypted** with a KDF | `BEGIN PRIVATE KEY` / `BEGIN ENCRYPTED PRIVATE KEY` |
| **PKCS#10** | Certificate Signing Request (CSR) | `BEGIN CERTIFICATE REQUEST`, `.csr` |
| **PKCS#11** | "Cryptoki" — a C **API** to talk to crypto tokens / **HSMs** / smart cards | not a file format at all |
| **PKCS#12** | Bundle of cert + private key + chain, password-protected | `.pfx` / `.p12` |

Key distinctions interviewers love:

- **PKCS#1 vs PKCS#8.** PKCS#1 is RSA-specific (`BEGIN RSA PRIVATE KEY`). PKCS#8 is algorithm-agnostic — it wraps the key with an `AlgorithmIdentifier`, so the same container works for RSA, ECDSA, Ed25519. Modern systems prefer PKCS#8. Java's `KeyFactory` expects PKCS#8 (`PKCS8EncodedKeySpec`); it can't parse raw PKCS#1 without conversion.
- **PKCS#7 vs PKCS#12.** Both can carry multiple certs. PKCS#7 **never** carries a private key — it's chains/CMS only. PKCS#12 carries the **private key plus** certs and is encrypted. If someone hands you a `.p7b` expecting their key inside, it isn't there.
- **PKCS#11 is not a file.** It's the standardized API (`C_Sign`, `C_FindObjects`, etc.) that lets OpenSSL/SoftHSM/YubiHSM/Luna expose keys without exporting them. This is how a CA's signing key can live in an HSM and never touch disk — central to any serious PKI, including a managed/cloud issuing CA.

### 5. How private keys are protected at rest

A bare private key (PKCS#1 or unencrypted PKCS#8) is plaintext — anyone who reads the file owns the identity. Protection options:

- **Legacy PKCS#1 encryption** (`Proc-Type: 4,ENCRYPTED` + `DEK-Info: AES-256-CBC,<IV>` headers). The passphrase is run through a weak MD5-based KDF. **Avoid** — historically insecure.
- **PKCS#8 encryption** — passphrase → strong **KDF** (PBKDF2, or modern `scrypt`) → symmetric key → encrypts the inner key. This is the right way for files. `BEGIN ENCRYPTED PRIVATE KEY`.
- **PKCS#12** — uses PBKDF2/PBES2 for the bag encryption *and* a separate MAC (integrity). Two passwords are *possible* (key vs MAC) but tools usually use one.
- **HSM / TPM / PKCS#11 token** — the key is generated *inside* hardware and is **non-exportable**. There is no file to steal; you can only ask the device to sign. This is the gold standard for CA signing keys and for high-value EAP-TLS clients on managed devices.

> **SecureW2 context:** In passwordless Wi-Fi (EAP-TLS), the client private key ideally lives in the device's secure enclave / TPM / Keychain / Android Keystore — non-exportable, bound to hardware. The Cloud RADIUS validates the *certificate*; the *key* never leaves the device. That's the entire security advantage over PEAP/MSCHAPv2 credentials, which are phishable.

### 6. Keystores: where formats meet platforms

- **PEM bundle** — Unix/nginx/Apache/HAProxy world. Just concatenated PEM blocks. Simple, transparent.
- **PKCS#12** — the cross-platform binary bundle. Importable into Windows, macOS, Java, browsers.
- **JKS (Java KeyStore)** — Java's proprietary format. **Deprecated since Java 9**; the default keystore type is now PKCS#12. `keytool` manages both. New work should use PKCS#12, not JKS.
- **Windows Certificate Store** — registry/CAPI-backed (LocalMachine vs CurrentUser; `My`, `Root`, `CA` stores). Import via `certutil`, MMC, or by double-clicking a `.pfx`.
- **macOS Keychain** — login vs System keychain; managed via `security` CLI or Keychain Access.

The migration takeaway: **PKCS#12 is the universal interchange format.** When you need a key+cert to move between platforms, export to `.p12`.

---

## PRACTICE

```bash
# --- 0. Set up a throwaway cert + key to play with ---
# Generate an EC private key (PKCS#8, unencrypted) and a self-signed cert in one shot
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout leaf.key -out leaf.crt -days 365 -nodes \
  -subj "/CN=device01.corp.example/O=SecureW2 Lab"
# leaf.key  -> BEGIN PRIVATE KEY (PKCS#8, plaintext)
# leaf.crt  -> BEGIN CERTIFICATE (PEM)
```

```bash
# --- 1. Inspect: what am I actually looking at? ---
head -1 leaf.crt                      # see the BEGIN label
file leaf.crt leaf.key                # PEM text vs data
openssl x509  -in leaf.crt -noout -text   # decode the cert
openssl pkey  -in leaf.key -noout -text   # decode the key (works for RSA/EC/Ed25519)
openssl asn1parse -in leaf.crt            # walk the raw ASN.1 TLV structure
```

```bash
# --- 2. PEM <-> DER conversions (encoding layer only) ---
# Certificate: PEM -> DER
openssl x509 -in leaf.crt -outform DER -out leaf.der
# Certificate: DER -> PEM
openssl x509 -inform DER -in leaf.der -out leaf-roundtrip.crt
# Private key: PEM -> DER (PKCS#8)
openssl pkey -in leaf.key -outform DER -out leaf.key.der
```

```bash
# --- 3. Key format conversions (PKCS#1 <-> PKCS#8, encrypt at rest) ---
# Make a PKCS#1 RSA key, then convert to PKCS#8
openssl genrsa -out rsa-pkcs1.key 2048                     # BEGIN RSA PRIVATE KEY (PKCS#1)
openssl pkcs8 -topk8 -nocrypt -in rsa-pkcs1.key -out rsa-pkcs8.key   # BEGIN PRIVATE KEY
# Encrypt a key at rest with a modern KDF (scrypt) -> ENCRYPTED PRIVATE KEY
openssl pkcs8 -topk8 -scrypt -in rsa-pkcs8.key -out rsa-enc.key      # prompts for passphrase
# Go back to PKCS#1 if some legacy tool insists
openssl rsa -in rsa-pkcs8.key -out rsa-back-to-pkcs1.key -traditional
```

```bash
# --- 4. Build a PKCS#12 (.pfx) bundle: key + cert + chain ---
# (Assume chain.pem holds the intermediate(s); omit -certfile if none yet)
openssl pkcs12 -export \
  -inkey leaf.key -in leaf.crt \
  -certfile chain.pem \
  -name "device01" \
  -out device01.pfx                  # prompts for export password
# Inspect the bundle (don't print the key)
openssl pkcs12 -in device01.pfx -info -nokeys
```

```bash
# --- 5. Extract pieces back OUT of a PKCS#12 ---
openssl pkcs12 -in device01.pfx -nokeys -clcerts -out extracted-leaf.crt   # leaf only
openssl pkcs12 -in device01.pfx -nokeys -cacerts -out extracted-chain.crt  # chain/CA certs
openssl pkcs12 -in device01.pfx -nocerts -out extracted.key                # private key (re-encrypted)
openssl pkcs12 -in device01.pfx -nocerts -nodes -out extracted-plain.key   # key, NO encryption
```

```bash
# --- 6. PKCS#7 (.p7b): chains, never keys ---
# Bundle certs into a PKCS#7 (typical for shipping a chain to Windows/IIS)
openssl crl2pkcs7 -nocrl -certfile leaf.crt -certfile chain.pem -out bundle.p7b
# View what's inside a .p7b (prints the certs)
openssl pkcs7 -in bundle.p7b -print_certs -noout
# DER .p7b -> PEM certs
openssl pkcs7 -inform DER -in bundle.p7b -print_certs -out chain-from-p7b.pem
```

```bash
# --- 7. Java keytool basics (PKCS#12 is the modern default) ---
# Create a PKCS#12 keystore with a generated keypair
keytool -genkeypair -alias device01 -keyalg EC -groupname secp256r1 \
  -storetype PKCS12 -keystore ks.p12 -dname "CN=device01.corp.example" \
  -storepass changeit
# List entries
keytool -list -v -storetype PKCS12 -keystore ks.p12 -storepass changeit
# Import an existing PKCS#12 into a keystore (interop with OpenSSL output)
keytool -importkeystore -srckeystore device01.pfx -srcstoretype PKCS12 \
  -destkeystore ks-import.p12 -deststoretype PKCS12
# Migrate a legacy JKS -> PKCS12
keytool -importkeystore -srckeystore legacy.jks -srcstoretype JKS \
  -destkeystore migrated.p12 -deststoretype PKCS12
```

**Exercises:**
1. Take `leaf.crt`, convert it PEM→DER→PEM, and prove the round-trip is byte-identical with `cmp`/`sha256sum`. Explain why DER's "distinguished" property guarantees this.
2. Given an unknown file, write a one-liner that decides whether it is PEM cert, DER cert, PKCS#12, or PKCS#7 — *without* trusting the extension.
3. Generate an RSA key as PKCS#1, convert to encrypted PKCS#8 with `-scrypt`, then inspect the ASN.1 with `openssl asn1parse` and identify the KDF parameters (salt, iteration/cost).
4. Build a `.pfx` containing leaf+key+chain, then extract only the leaf and only the unencrypted key. Confirm the extracted key matches the original via public-key fingerprint (`openssl pkey -pubout`).
5. Create a `.p7b` from a leaf+chain and verify with `-print_certs` that **no private key** is present. Explain to a colleague why you'd ship a `.p7b` to IIS but a `.pfx` to a Wi-Fi supplicant.
6. Import an OpenSSL-generated `.pfx` into a Java PKCS#12 keystore with `keytool` and list it — confirm interop works without conversion.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. A file is named `cert.crt` but a tool says "unable to load certificate." How do you diagnose it in under a minute?**
The extension is meaningless; check the actual bytes. `head -1 cert.crt` — if you see `-----BEGIN CERTIFICATE-----` it's PEM; if you see binary garbage it's likely DER (or a PKCS#7/PKCS#12 mislabeled). Try `openssl x509 -in cert.crt -noout -text` and if that fails `openssl x509 -inform DER -in cert.crt -noout -text`. If both fail, it may be a chain in PKCS#7 (`openssl pkcs7 -print_certs`) or the file labeled `.crt` is actually a CSR or a key. The lesson: trust the magic bytes / BEGIN line, never the extension.

**Q2. What's the difference between `BEGIN RSA PRIVATE KEY`, `BEGIN PRIVATE KEY`, and `BEGIN ENCRYPTED PRIVATE KEY`?**
`RSA PRIVATE KEY` is **PKCS#1** — RSA-specific, no algorithm wrapper, almost always plaintext. `PRIVATE KEY` is **PKCS#8 unencrypted** — algorithm-agnostic (RSA/EC/Ed25519), carries an `AlgorithmIdentifier`. `ENCRYPTED PRIVATE KEY` is **PKCS#8 encrypted** — the key is protected by a passphrase-derived KDF (PBKDF2/scrypt) under PBES2. They are different ASN.1 structures, which is why a parser that only knows one will reject the others. Java needs PKCS#8; convert PKCS#1 with `openssl pkcs8 -topk8`.

**Q3. You receive a `.p7b` and need the private key out of it. What do you tell the requester?**
There is no private key in a PKCS#7 file — by design it carries certificates (and optionally CRLs/CMS signed content) only. PKCS#7 is for distributing **chains**, not keys. If they need a key+cert bundle, they want a **PKCS#12** (`.pfx`/`.p12`), and they need to re-export from wherever the key actually lives. A common cause of this confusion: Windows exports a "Certificate (no private key)" as `.p7b` and a "Certificate with private key" as `.pfx`.

**Q4. Why is DER used to compute signatures rather than PEM or BER?**
Because signing requires a **single canonical byte representation**. BER allows multiple valid encodings (e.g., indefinite lengths, varied length forms), so the same logical value could produce different bytes and thus different signatures — a verifier couldn't reliably reproduce the signed input. DER eliminates that ambiguity (definite lengths, sorted SETs, no redundant encodings). PEM is just base64 of DER, so the underlying signed bytes are still DER. Signatures are over the DER-encoded `TBSCertificate`.

**Q5. Is converting PEM↔DER lossy? Is converting PKCS#1↔PKCS#8 lossy?**
PEM↔DER is a pure **encoding** change — lossless and reversible to identical bytes (same DER underneath). PKCS#1↔PKCS#8 changes the **structure/wrapper**: the raw key material is preserved, but PKCS#8 adds an `AlgorithmIdentifier`, and if you add encryption you introduce KDF/salt that obviously changes the bytes. The *key* is the same (same public key, same signing capability); the container differs. So "lossless" depends on whether you mean bytes or cryptographic identity.

**Q6. Why prefer PKCS#12 over JKS in modern Java, and what changed?**
Since Java 9 the default keystore type is **PKCS#12**, not the proprietary JKS. PKCS#12 is a standardized, cross-platform, well-scrutinized format with stronger, configurable encryption (PBES2/PBKDF2) and a MAC for integrity; JKS used weaker proprietary protection and is Java-only. Using PKCS#12 means the same bundle interoperates with OpenSSL, Windows, macOS, and browsers without conversion. JKS still exists for legacy compatibility, and `keytool -importkeystore` migrates it.

**Q7. In EAP-TLS, where should the client's private key live, and how does that relate to these formats?**
Ideally the key is generated **inside hardware** (TPM, Secure Enclave, Android Keystore, smart card) and is **non-exportable** — accessed via a PKCS#11-style interface, never serialized to PKCS#8/PKCS#12 on disk. When you must provision via a file, you ship a password-protected `.pfx`, but the *better* design (SecureW2's model) is on-device key generation so no key file ever exists to be stolen or copied. The RADIUS server only ever sees and validates the *certificate*; possession of the private key is proven cryptographically during the TLS handshake, not by transmitting the key.

**Q8. A `.pfx` imports fine on Windows but a Linux tool rejects it. What's a likely cause?**
Algorithm/cipher mismatch. Modern OpenSSL 3.x defaults PKCS#12 to AES-based PBES2, while older Windows/Java exports (or `legacy` mode) use RC2/3DES (`pbeWithSHA1And40BitRC2-CBC`). OpenSSL 3 dropped weak legacy ciphers from the default provider, so importing an old RC2-protected `.pfx` fails unless you pass `-legacy` (and load the legacy provider). Conversely, exporting with OpenSSL 3 defaults can break ancient importers. Fix by re-exporting with a compatible cipher (`openssl pkcs12 -export -certpbe AES-256-CBC -keypbe AES-256-CBC ...` or `-legacy` for old peers).

➡ Next: [Day 05 — CA Hierarchy & Chain of Trust](day-05-ca-hierarchy-chain-of-trust.md)
