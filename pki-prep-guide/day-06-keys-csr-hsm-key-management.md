# Day 06 — Keys, CSRs, HSMs & Key Management

## THEORY

### 1. The Whole Game: A Certificate Is Just a Signed Statement About a Key

Before we touch a single command, internalize this: **a certificate is a CA's signed assertion that "this public key belongs to this identity."** Everything in PKI orbits around the *private key*. The cert is public, copyable, disposable. The private key is the crown jewel. Lose control of the private key and the certificate — and the entire identity it represents — is worthless.

So the central question of this entire day is: **where does the private key live, who can touch it, and can it ever leave?**

This matters more than people think. In a SecureW2-style deployment, when a laptop authenticates to Wi-Fi via EAP-TLS, the RADIUS server's trust decision ultimately rests on whether *only that laptop* could have signed the TLS handshake with the private key matching the cert. If the key was generated centrally and emailed around, that guarantee is gone.

### 2. Where Should Key Pairs Be Generated? On-Device vs Central

There are two models:

| Model | Where key is born | Private key travels? | Non-repudiation |
|-------|-------------------|---------------------|-----------------|
| **On-device (decentralized)** | On the endpoint (laptop TPM, phone Secure Enclave, smart card) | **Never leaves** | Strong — only that device could sign |
| **Central generation** | On a server/CA, then pushed to device | Yes — must be transported | Weak — server (and anyone who saw it in transit) also had the key |

**Why on-device is almost always better:**

- **Non-repudiation**: If a key never existed anywhere except the secure hardware of one device, then a signature made with it *must* have come from that device. The moment a central server generates the key, you can no longer prove the device — and not the server admin — produced a signature. For signing/authentication keys, non-repudiation is the whole point.
- **No transport problem**: Central generation forces you to securely ship a private key to the device (PKCS#12/.pfx over some channel). That channel becomes an attack surface. On-device generation means *only the public key (in a CSR) ever travels*, and public keys are public — no secrecy needed.
- **Hardware binding**: Generate inside a TPM/Secure Enclave with a non-exportable flag and the key is cryptographically welded to that one chip. Reimaging, cloning, or copying the disk does not move the key.

This is exactly how a modern SecureW2 + MDM (Intune/Jamf) onboarding flow works: the device generates its own key pair in hardware, builds a CSR, and only the CSR goes up to the SCEP/EST gateway. The CA never sees the private key.

> **Gotcha — the exception**: *Encryption* keys (e.g., S/MIME, BitLocker recovery, EFS) sometimes *should* be centrally generated or escrowed, because if the user loses the key you must recover the encrypted data. We split this by key usage — see escrow below. Signing/auth keys: on-device, no escrow. Encryption keys: escrow allowed.

### 3. The CSR — PKCS#10 Certificate Signing Request

A CSR is the formal "please issue me a certificate" message. It is defined by **PKCS#10 (RFC 2986)**. The device generates its key pair, then wraps a *request* around the **public key**.

**What a CSR actually contains:**

- The **subject's public key** (the public half only — never the private key).
- The proposed **subject DN** (CN, O, OU, etc.) — a *request*, not a guarantee.
- Optionally **requested extensions** (e.g., a `subjectAltName` the requester would like).
- A **signature over the entire CSR, made with the requester's private key.**

That last point is critical:

**Proof of Possession (PoP):** The CSR is self-signed with the private key that pairs with the public key inside it. When the CA verifies this signature *using the public key in the CSR*, it proves the requester actually holds the matching private key. Without PoP, I could submit a CSR containing *your* public key and try to get a cert issued for an identity I can't actually use — PoP closes that hole.

**What the CA takes from the CSR and what it does NOT:**

| Field | Does the CA trust it? |
|-------|----------------------|
| Public key | **Yes** — copied verbatim into the cert |
| PoP signature | **Verified**, then discarded |
| Subject CN/DN | **Maybe** — usually overridden/validated against policy |
| Requested SANs | **Maybe** — validated, frequently rewritten |
| Requested validity period | **No** — set by the CA/template |
| Requested EKU / key usage | **No** — set by the CA/template |
| Requested CA:TRUE / path length | **Absolutely not** |

> **The single most-misunderstood point in PKI:** *The CSR is a request, not an order.* The requester proposes; the CA disposes. The **CA**, driven by its **certificate template/profile**, decides the EKU (clientAuth? serverAuth?), the validity, the key usage bits, and whether to trust the subject. Why? Because the requester has every incentive to ask for too much (longer life, more powers, a SAN they don't own). Authority must live with the issuer, not the supplicant. A correctly configured CA *ignores or validates* requested EKU/validity rather than copying them.

### 4. Where Private Keys Live — From Soft Files to HSMs

Ordered roughly weakest to strongest:

1. **Software keystore** — key in a file (PEM, PKCS#12/.pfx, Java keystore, Windows DPAPI store). Easiest, most portable, **least secure** — the key bytes exist on disk/RAM and can be exfiltrated by malware or a stolen disk.
2. **TPM (Trusted Platform Module)** — a soldered-on crypto chip in most business laptops. Keys can be generated *non-exportable*; signing happens inside the chip. Resists disk theft and cloning. The backbone of Windows device certs / "Windows Hello for Business."
3. **Secure Enclave (Apple)** — Apple's equivalent coprocessor on Macs/iPhones. Keys never leave; signing done in-enclave. Used by Jamf/iOS device certs.
4. **Smart cards / PIV / YubiKey** — removable hardware token, key non-exportable, gated by PIN. Used for user auth, government PIV/CAC.
5. **HSM (Hardware Security Module)** — a dedicated, tamper-resistant appliance or card (Thales Luna, Entrust nShield, AWS CloudHSM, YubiHSM). This is where **CA private keys** live. Keys are generated inside and *cannot* be extracted in plaintext. All signing operations happen inside the HSM boundary.

**FIPS 140-2 / 140-3 levels** (the US standard for crypto module security; 140-3 supersedes 140-2):

| Level | Roughly means |
|-------|---------------|
| **Level 1** | Basic; software crypto can qualify. No physical security required. |
| **Level 2** | Tamper-*evident* (you can see it was opened) + role-based auth. |
| **Level 3** | Tamper-*resistant/responsive* — actively zeroizes keys on physical intrusion; identity-based auth. **This is the typical bar for a production CA HSM.** |
| **Level 4** | Highest — full envelope protection, resists environmental attacks (voltage/temperature). |

> **Interview-grade nuance:** FIPS 140-2/3 validates the *module*, not your deployment. A Level-3 HSM badly administered is still insecure. And "FIPS-compliant" ≠ "FIPS-validated" — validated means it carries a CMVP certificate number.

**PKCS#11** is the standard C API ("Cryptoki") that lets software talk to any HSM/token without caring about the vendor. Your CA software loads a vendor `.so`/`.dll` PKCS#11 module and calls `C_Sign`, `C_GenerateKeyPair`, etc. It's the universal plug between software and hardware crypto. (Microsoft's equivalent is CNG/KSP; PKCS#11 is the cross-platform one.)

### 5. The Root CA Key Ceremony — M-of-N, Air-Gapped, Witnessed

The root CA's private key is the single most valuable secret in your PKI. If it leaks, every certificate that chains to it must be considered compromised and the whole trust hierarchy rebuilt. So root keys are created in a **key ceremony**:

- **Air-gapped, offline** machine — the root CA never touches a network. It comes out of the safe only to sign new intermediate CAs or CRLs, then goes back.
- **Generated inside an HSM** (FIPS 140-2/3 Level 3+), non-exportable.
- **M-of-N control (Shamir's Secret Sharing / quorum)**: The ability to *activate* the HSM key is split into **N** physical tokens (smart cards), and any **M** of them are required to operate it — e.g., **3-of-5**. No single person ("no single point of compromise") can use the root key; you need a quorum of trusted custodians physically present.
- **Witnessed and scripted**: A written ceremony script, multiple witnesses, video recording, signed logs. Tokens go into separate safes, ideally held by different people in different locations.
- **Tamper-evident bags**, serial-number logging, and an auditor present.

> Why this much theater? Because you can rotate an intermediate CA in a weekend, but rotating a 20-year root that's embedded in trust stores worldwide is a multi-year nightmare. The ceremony's rigor is proportional to how irreplaceable the key is.

### 6. Key Lifecycle: Generation → Use → Escrow → Rotation → Destruction

- **Generation** — proper entropy, right algorithm/strength, right storage (see above).
- **Escrow vs no-escrow** — this is decided **by key usage**:
  - **Signing / authentication keys → NO escrow.** If you keep a copy, you destroy non-repudiation (someone else had the key). Lost signing key? You just enroll a new one. Never back these up.
  - **Encryption keys → escrow (key archival).** If a user loses their encryption key, the data encrypted to it is gone forever. So you archive a copy in the CA's key-recovery database, protected by separate recovery agents. This is why you generate **dual key pairs** for things like S/MIME — one signing key (on-device, no escrow) and one encryption key (escrowed).
- **Rotation** — keys have a finite safe lifetime. Rotate before the algorithm weakens, before the validity expires, or after suspected exposure. Overlap old and new during cutover.
- **Destruction** — when a key retires, **zeroize** it (cryptographic erase). For an HSM, that means deleting the key object / decommissioning per FIPS; for software keys, secure wipe. A revoked-but-not-destroyed private key is still a liability.

### 7. Choosing Crypto Strength: RSA vs ECC

| Choice | Strength | Pros | Cons / Gotchas |
|--------|----------|------|----------------|
| **RSA-2048** | ~112-bit | Universal compatibility, "good enough" today | Large keys/signatures; slower; being phased toward 3072 |
| **RSA-3072** | ~128-bit | Stronger, future-proofing | Slower still, bigger |
| **ECC P-256 (secp256r1)** | ~128-bit | Small, fast, low power — ideal for phones/IoT | Older middleware may not support it |
| **ECC P-384** | ~192-bit | High assurance | Less universal |

**Rules of thumb for practitioners:**

- RSA-2048 is the safe default for *broad compatibility* (legacy RADIUS supplicants, old switches).
- **ECC P-256 is the better choice for device/mobile certs** — same ~128-bit security as RSA-3072 but a fraction of the key size and CPU. Battery-friendly. This is why modern MDM-issued device certs increasingly use EC.
- **Match the chain**: a leaf signed by a CA should use a comparable/strong-enough hash and the CA key should be ≥ the leaf. Roots are often RSA-4096 or P-384 for their long life.
- Never use RSA-1024 or SHA-1. Both are dead.
- Looking ahead: **post-quantum (ML-DSA / ML-KEM)** is coming; design for crypto-agility (ability to swap algorithms) now.

---

## PRACTICE

```bash
# ── 1. Generate an RSA-2048 private key (software keystore, for learning) ──
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out device.key
# Inspect it
openssl pkey -in device.key -text -noout | head -20

# ── 2. Generate an ECC P-256 key (preferred for device certs) ──
openssl ecparam -name prime256v1 -genkey -noout -out device-ec.key
openssl pkey -in device-ec.key -text -noout

# ── 3. Build a simple CSR (interactive prompts for the subject DN) ──
openssl req -new -key device.key -out device.csr \
  -subj "/C=US/O=SecureW2/OU=Devices/CN=laptop-7f3a.acme.example"

# ── 4. Build a CSR WITH SubjectAltName via a config file ──
cat > csr.cnf <<'EOF'
[ req ]
default_bits       = 2048
prompt             = no
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
C  = US
O  = SecureW2
OU = Devices
CN = laptop-7f3a.acme.example

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = laptop-7f3a.acme.example
DNS.2 = laptop-7f3a.local
# For a user/EAP-TLS cert you'd often use an otherName UPN or email instead:
email.1 = vamsi.h@securew2.com
EOF

openssl req -new -key device.key -out device-san.csr -config csr.cnf

# ── 5. Inspect a CSR — see exactly what you're asking the CA for ──
openssl req -in device-san.csr -text -noout -verify
# Note in the output:
#   - "Subject:" is what you REQUESTED (CA may override)
#   - "Requested Extensions:" shows your SAN
#   - "Signature ... self-signature verify OK"  <-- this line IS Proof of Possession

# ── 6. Prove Proof-of-Possession manually: verify the CSR self-signature ──
openssl req -in device-san.csr -noout -verify
# "verify OK" => the private key matching the embedded public key signed this CSR.

# ── 7. Confirm a private key matches a CSR/cert (modulus / pubkey match) ──
openssl req  -in device-san.csr -noout -pubkey | openssl md5
openssl pkey -in device.key -pubout        | openssl md5
# The two hashes must be identical.

# ── 8. Generate a key INSIDE a PKCS#11 token / HSM (key never leaves) ──
# (requires a token + module, e.g. SoftHSM2 for practice, or a YubiHSM/Luna in prod)
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --login --pin 1234 \
  --keypairgen --key-type EC:prime256v1 --label "device-key" --id 01
# Then generate a CSR that references the on-token key (signing happens IN the token):
OPENSSL_CONF=pkcs11.cnf openssl req -new -engine pkcs11 -keyform engine \
  -key "pkcs11:object=device-key;type=private" -out hsm-device.csr \
  -subj "/CN=laptop-7f3a.acme.example"

# ── 9. Practice an M-of-N split with Shamir's Secret Sharing (ssss) ──
echo "super-secret-root-activation" | ssss-split -t 3 -n 5   # 3-of-5 quorum
# ...collect any 3 shares to reconstruct:
ssss-combine -t 3
```

**Exercises:**

1. Generate an EC P-256 key and an RSA-2048 key. Compare the byte sizes of the resulting CSRs and explain why EC is preferred for IoT/mobile device certs.
2. Create a CSR requesting `basicConstraints = CA:TRUE` and `keyUsage = keyCertSign`. Explain why a properly configured CA will *ignore* this request, and where that decision actually lives.
3. Build a CSR with two DNS SANs and one email SAN, then prove (with two `openssl ... | md5` commands) that your private key matches the public key inside the CSR.
4. Using SoftHSM2, generate a non-exportable key and attempt to export it. Document the error — that failure *is* the security guarantee.
5. Write a one-page "key ceremony script" for a 3-of-5 root CA generation: list roles (custodians, witness, auditor), steps, and what gets logged.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. A junior engineer says "the CSR contains the private key, so we must send it over TLS." Correct them.**
The CSR contains only the **public key** plus a self-signature made *with* the private key. The private key never appears in a CSR and never should. You *can* send a CSR in cleartext (it's public information). The reason on-device generation is secure is precisely that only the CSR — never the secret — leaves the device. If your enrollment design transports a private key, you've adopted central generation and forfeited non-repudiation.

**Q2. Why does the CA override the EKU and validity period that the requester put in the CSR? Isn't the requester the authority on what it needs?**
No — the requester is the *least* trustworthy party to decide its own privileges and lifetime. The CSR is a request; the CA's **template/profile** is policy. Authority must rest with the issuer, who is accountable for the trust chain. If the CA honored requested validity, anyone could mint a 100-year cert; if it honored requested EKU, a device could ask for `serverAuth` or even `CA:TRUE`. The CA validates the *identity* (subject/SAN) and *assigns* the powers (EKU, key usage, validity) from policy.

**Q3. When is it acceptable — even required — to centrally generate or escrow a private key?**
For **encryption (data-at-rest / key-encipherment) keys**, where losing the key means losing the data: S/MIME encryption keys, BitLocker recovery, EFS. These are archived under key-recovery agents so data is recoverable. It is **never** acceptable for **signing/authentication** keys, because escrow means someone else holds the key, which destroys non-repudiation. The clean design is **dual key pairs**: an on-device, no-escrow signing key and an escrowed encryption key.

**Q4. What exactly is "Proof of Possession" and what attack does it prevent?**
PoP is the CSR's self-signature: the request is signed with the private key matching the public key it carries, and the CA verifies that signature using that embedded public key. It prevents an attacker from submitting a CSR containing *someone else's* public key to obtain a certificate they can't actually use — i.e., binding an identity to a key the requester doesn't control. PoP proves "I hold the private key for the public key I'm submitting."

**Q5. We have a TPM in every laptop. Why is a key generated as "non-exportable" in the TPM stronger than the same key generated by OpenSSL and imported into the TPM?**
If OpenSSL generated it, the plaintext key existed in normal RAM/disk at least momentarily and could have been copied, swapped to disk, or read by malware before import — you can no longer prove uniqueness. A key *born* in the TPM with the non-exportable flag has never existed in plaintext outside the chip; cloning the disk or reimaging does not move it. The security property is "the key has only ever existed in one tamper-resistant boundary," and importing breaks that from the start.

**Q6. Explain M-of-N for a root CA. Why not just give the key to one trusted admin?**
M-of-N (quorum, via Shamir secret sharing or HSM smart-card sets, e.g. 3-of-5) splits the authority to *activate* the root key across N custodians, requiring M of them physically present to operate it. A single trusted admin is a single point of compromise — coercion, bribery, error, or a stolen token defeats the entire PKI. Quorum control means no one person can misuse the root, and the loss/compromise of fewer than M shares is survivable. It converts "trust one human" into "trust that M humans don't all collude."

**Q7. A FIPS 140-2 Level 3 HSM and a FIPS 140-2 Level 1 software module both "do AES-256." Is the crypto stronger in the HSM?**
The *algorithm* strength is identical — AES-256 is AES-256. What differs is **key protection and the operational boundary**: Level 3 gives tamper-resistance/zeroization, identity-based auth, and keys that can't be extracted; Level 1 is software with no physical protection. FIPS levels rate the module's resistance to compromise, not the math. The HSM protects the *key*, which is what actually matters in practice.

**Q8. In a SecureW2 + Intune EAP-TLS rollout, where is the device key generated, what travels to the cloud, and why is that the secure design?**
The device (via Intune's SCEP/PKCS profile) has its **TPM/Secure Enclave generate the key pair locally, non-exportable**. The device builds a **CSR** and sends only that — the public key — through the MDM to the SecureW2 SCEP/EST gateway and CA. The CA validates the request against policy, assigns the `clientAuth` EKU and validity, and returns the signed cert. Because the private key never leaves the device's hardware, only that device can complete the EAP-TLS handshake, giving you per-device non-repudiation and immunity to disk-cloning attacks.

**Q9. Why might you pick ECC P-256 over RSA-3072 for 50,000 IoT sensors, but keep the offline root on RSA-4096 / P-384?**
P-256 gives ~128-bit security at a tiny key/signature size and low CPU/battery cost — ideal for constrained, high-volume devices doing frequent TLS handshakes; RSA-3072 gives the same security but is far heavier. The root, by contrast, signs rarely, lives offline for 20+ years, and must resist long-horizon attacks, so you over-provision its strength (RSA-4096 or P-384) and don't care about its performance. Match the algorithm to the *lifetime and workload* of each key, not a one-size-fits-all policy.

➡ Next: [Day 07 — Certificate Enrollment Protocols](day-07-enrollment-protocols-scep-est-acme.md)
