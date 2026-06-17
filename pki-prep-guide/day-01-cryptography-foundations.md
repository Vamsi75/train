# Day 01 — Cryptography Foundations

> You cannot reason about PKI, X.509, or EAP-TLS until the primitives underneath them are second nature. Every certificate is a signed assertion; every TLS handshake is a key exchange plus authentication; every "passwordless" SecureW2 login is ECDSA/RSA math wrapped in protocol. This day builds that foundation.

## THEORY

### 1. The Three Pillars (and what they actually buy you)

Cryptography services map to security goals. Keep them straight — interviewers love conflating them.

| Goal | Primitive | What it does NOT give you |
|------|-----------|---------------------------|
| **Confidentiality** | Symmetric (AES), or asymmetric for key wrap | No integrity, no authenticity by itself |
| **Integrity** | Hash (SHA-2/3) | Anyone can recompute a hash — no authenticity |
| **Authenticity / Integrity (keyed)** | MAC / HMAC | Symmetric — both parties share the secret, so no non-repudiation |
| **Authenticity + Non-repudiation** | Digital signature (RSA/ECDSA/EdDSA) | Not confidentiality |
| **Key agreement** | DH / ECDHE | Not authentication — MITM is trivial without it |

The classic gotcha: **encryption alone does not protect integrity.** AES-CTR ciphertext can be bit-flipped to predictably flip plaintext bits. That is *the* reason AEAD modes (GCM, ChaCha20-Poly1305) exist and why "encrypt-then-MAC" is the only safe composition order.

### 2. Symmetric Cryptography

One shared key, used for both encrypt and decrypt. Fast (hardware AES-NI does multiple GB/s), but the key-distribution problem is unsolved by symmetric crypto alone — that is literally why asymmetric crypto and PKI exist.

**Block vs stream:**
- **Block cipher** (AES) operates on fixed-size blocks (128 bits for AES, regardless of key size). Needs a *mode of operation* to handle messages longer than one block.
- **Stream cipher** (ChaCha20, RC4-dead) generates a keystream XORed with plaintext. CTR mode turns a block cipher into a stream cipher.

**AES key sizes:** AES-128, AES-192, AES-256. Block size is always 128 bits. AES-256 is preferred for "post-quantum hedging" because Grover's algorithm halves the effective brute-force strength (256 → 128 bits effective, still safe).

**Modes of operation — know the failure stories:**

| Mode | Type | Auth? | Notes / Gotcha |
|------|------|-------|----------------|
| **ECB** | Block | No | Never use. Identical plaintext blocks → identical ciphertext blocks. The "ECB penguin" is visible. |
| **CBC** | Block | No | Needs random IV. Padding-oracle attacks (POODLE, Lucky13) if you decrypt-then-check-MAC or leak padding errors. |
| **CTR** | Stream-like | No | Parallelizable, no padding. Catastrophic on nonce reuse (keystream reuse → XOR of plaintexts). |
| **GCM** | AEAD | **Yes** | CTR + GHASH auth tag. Nonce reuse destroys both confidentiality AND authenticity (forges the auth key). 96-bit nonce standard. |
| **ChaCha20-Poly1305** | AEAD | **Yes** | No AES-NI needed; great on mobile/embedded. TLS 1.3 default alongside AES-GCM. |

> **Why TLS 1.3 dropped CBC and everything non-AEAD:** decades of padding-oracle and MAC-then-encrypt disasters. TLS 1.3 only allows AEAD ciphers. This is directly relevant to RADIUS-over-TLS (RadSec) and EAP tunnels.

### 3. Asymmetric (Public-Key) Cryptography

A **key pair**: a public key (shareable) and a private key (secret). What one key does, only the other can undo. Two distinct uses:

- **Encryption:** encrypt with *public*, decrypt with *private* (confidentiality to the key owner).
- **Signing:** sign with *private*, verify with *public* (authenticity from the key owner).

Asymmetric crypto is ~1000x slower than symmetric, so in practice it is used to (a) wrap/agree a symmetric session key and (b) sign hashes — never to bulk-encrypt data.

**RSA — math intuition:**
- Pick two large primes `p`, `q`; `n = p·q`. Security rests on the hardness of factoring `n`.
- Public exponent `e` (usually 65537), private exponent `d` with `e·d ≡ 1 (mod φ(n))`.
- Sign/decrypt: `m^d mod n`. Verify/encrypt: `c^e mod n`.
- **Padding is mandatory and non-optional:** use **OAEP** for encryption, **PSS** (or at minimum PKCS#1 v1.5) for signatures. "Textbook RSA" with no padding is broken (malleable, deterministic).

**ECC / ECDSA — math intuition:**
- Operates over points on an elliptic curve. Security rests on the **Elliptic Curve Discrete Log Problem (ECDLP)**: given points `P` and `Q = k·P`, recovering scalar `k` is infeasible.
- Much smaller keys for equivalent strength → smaller certs, faster handshakes, less power. This is why IoT, mobile, and modern Wi-Fi onboarding (SecureW2 device certs) increasingly default to ECC.
- Common curves: **P-256 (secp256r1 / prime256v1)**, P-384, P-521. The `r1` (NIST) curves dominate web/enterprise PKI.
- **ECDSA gotcha:** the per-signature nonce `k` MUST be unique and unpredictable. Reused or biased `k` leaks the private key (Sony PS3, several Bitcoin wallet thefts). **EdDSA fixes this** by deriving `k` deterministically from the message + key.

**EdDSA (Ed25519 / Ed448):**
- Modern signature scheme on twisted Edwards curves. Deterministic nonce, fast, resistant to many side channels, no need for a separate good RNG at signing time. Increasingly supported in TLS 1.3 and SSH; still ramping in enterprise PKI/CA tooling.

**Key-size equivalences (NIST, approximate "bits of security"):**

| Symmetric | RSA / DH modulus | ECC curve |
|-----------|------------------|-----------|
| 80-bit (legacy, dead) | 1024 | 160 |
| 112-bit | 2048 | 224 |
| 128-bit | 3072 | 256 (P-256) |
| 192-bit | 7680 | 384 (P-384) |
| 256-bit | 15360 | 521 (P-521) |

> Practitioner takeaway: **RSA-2048** is the floor for current use; RSA-3072 for long-lived roots; **P-256/P-384** when you want the same strength at a fraction of the size. Notice RSA scales terribly — RSA-15360 is absurd, while P-521 is tiny. That asymmetry is the whole argument for ECC.

### 4. Hash Functions

A hash maps arbitrary input → fixed-size digest. Required properties:

- **Preimage resistance:** given `h`, can't find `m` with `H(m)=h`.
- **Second-preimage resistance:** given `m1`, can't find `m2 ≠ m1` with same hash.
- **Collision resistance:** can't find *any* `m1 ≠ m2` with same hash. (Hardest to keep — birthday bound: an `n`-bit hash gives only `~2^(n/2)` collision resistance.)

| Algorithm | Output | Status |
|-----------|--------|--------|
| MD5 | 128-bit | **Broken** — practical collisions (Flame malware forged a CA cert via MD5). Never use. |
| SHA-1 | 160-bit | **Broken** — SHAttered collision (2017). Deprecated for certs since ~2017. |
| SHA-256 / SHA-384 / SHA-512 | SHA-2 family | Current standard. SHA-256 is the workhorse for certs/signatures. |
| SHA-3 (Keccak) | 224–512 | Different internal construction (sponge, not Merkle–Damgård). Hedge against SHA-2 structural breaks. |

> **Why collisions kill PKI:** if you can find two certificates with the same hash, a CA's signature over the "innocent" one is also valid over the malicious one. That is exactly how the Flame attack forged a Microsoft-trusted certificate. This is why CAs were forced off MD5 and SHA-1.

### 5. MAC and HMAC

- A **MAC** (Message Authentication Code) provides integrity + authenticity using a *shared secret*. Symmetric — so no non-repudiation (either party could have produced it).
- **HMAC** is a specific, proven construction: `HMAC(K,m) = H((K⊕opad) || H((K⊕ipad) || m))`. The nested structure defeats length-extension attacks that plague naive `H(K||m)` with Merkle–Damgård hashes.
- Used everywhere in TLS PRF/HKDF, RADIUS Message-Authenticator attribute, JWT (HS256), cookie signing.

> **MAC vs signature:** both prove integrity+authenticity. Use a MAC when both ends share a key and you want speed (TLS record protection, RADIUS). Use a signature when you need non-repudiation or one-to-many verification (certificates, code signing).

### 6. Digital Signatures — and why "hash-then-sign"

A signature binds a message to a key holder.

1. Compute `d = H(message)`.
2. Sign the *digest*: `sig = Sign(privkey, d)`.
3. Verify: recompute `H(message)`, then `Verify(pubkey, sig, digest)`.

**Why hash first?**
- **Performance:** RSA/ECDSA can only sign a small block (≈ key size). Hashing compresses any-length input to a fixed small digest.
- **Security:** signing the raw message with textbook RSA is malleable; signing a fixed-width hash with proper padding (PSS/PKCS#1) is what's actually secure.
- **This is the heart of X.509:** a CA hashes the `TBSCertificate` (the to-be-signed body) and signs that digest. The `signatureAlgorithm` field (e.g., `sha256WithRSAEncryption`, `ecdsa-with-SHA256`) names both the hash and the signature scheme. Mismatched/weak hash here = forgeable cert.

### 7. Key Exchange & Forward Secrecy

The problem: two parties who never met must agree on a shared symmetric key over a public channel.

**Diffie-Hellman (DH):**
- Public params `(g, p)`. Alice picks secret `a`, sends `g^a mod p`. Bob picks `b`, sends `g^b mod p`. Both compute `g^(ab) mod p`. An eavesdropper sees `g^a`, `g^b` but can't get `g^ab` (discrete log problem).
- **Unauthenticated DH is wide open to MITM** — that's why DH is *combined with* signatures/certificates (the server signs its DH params). This is the marriage of key exchange + PKI.

**ECDHE:** Elliptic-curve DH, **E**phemeral. The dominant TLS 1.3 key exchange.

**Forward Secrecy (PFS):**
- Ephemeral (`E` in ECDHE/DHE) means a fresh key pair per session, discarded after.
- Result: even if the server's *long-term private key is later stolen*, past recorded sessions stay safe — the attacker can't derive past session keys. Static RSA key transport (old TLS) has NO forward secrecy; one stolen key decrypts years of captured traffic. TLS 1.3 mandates (EC)DHE for exactly this reason.

### 8. Randomness & Entropy

Crypto lives or dies on unpredictable randomness — keys, IVs, nonces, ECDSA `k`, DH secrets.

- Use a **CSPRNG**: `/dev/urandom` (Linux), `getrandom()`, `CryptGenRandom`/`BCryptGenRandom` (Windows), `RAND_bytes` (OpenSSL). Never `rand()`/`Math.random()`.
- **Entropy starvation** on freshly-booted VMs/embedded devices caused the infamous Debian OpenSSL disaster (2008) and Taiwan TWNIC smart-card RSA key collisions — predictable keys you could factor.
- Reused/predictable nonces are the most common real-world key-compromise vector (see ECDSA `k` above, AES-GCM nonce reuse). When SecureW2 SCEP/onboarding generates a device key pair on a phone, it relies on the OS CSPRNG being healthy.

## PRACTICE

```bash
# ---------- RSA ----------
# Generate a 2048-bit RSA private key (use 3072+ for long-lived roots)
openssl genrsa -out rsa_priv.pem 2048

# Inspect it (note modulus, primes, exponents)
openssl rsa -in rsa_priv.pem -text -noout

# Extract the public key
openssl rsa -in rsa_priv.pem -pubout -out rsa_pub.pem

# ---------- ECC ----------
# List available curves
openssl ecparam -list_curves | grep -Ei 'prime256|secp384|secp521'

# Generate an EC private key on P-256 (prime256v1)
openssl ecparam -name prime256v1 -genkey -noout -out ec_priv.pem
openssl ec -in ec_priv.pem -text -noout
openssl ec -in ec_priv.pem -pubout -out ec_pub.pem

# ---------- Hashing ----------
echo -n "passwordless wifi" > msg.txt
openssl dgst -sha256 msg.txt
openssl dgst -sha512 msg.txt
openssl dgst -sha3-256 msg.txt
# Watch a 1-byte change cascade into a totally different digest (avalanche effect)
echo -n "passwordless wif1" | openssl dgst -sha256

# ---------- HMAC ----------
openssl dgst -sha256 -hmac "shared-secret" msg.txt

# ---------- Digital signatures (hash-then-sign) ----------
# RSA-PSS signature over the SHA-256 digest of msg.txt
openssl dgst -sha256 -sign rsa_priv.pem -sigopt rsa_padding_mode:pss -out msg.sig msg.txt
openssl dgst -sha256 -verify rsa_pub.pem -sigopt rsa_padding_mode:pss -signature msg.sig msg.txt

# ECDSA signature
openssl dgst -sha256 -sign ec_priv.pem -out msg_ec.sig msg.txt
openssl dgst -sha256 -verify ec_pub.pem -signature msg_ec.sig msg.txt

# Tamper test: change msg.txt and re-verify — it MUST fail
echo -n "tampered" >> msg.txt
openssl dgst -sha256 -verify ec_pub.pem -signature msg_ec.sig msg.txt   # expect: Verification Failure

# ---------- Symmetric encryption (AEAD-ish demo) ----------
# AES-256-CBC (note: -enc with a passphrase derives a key via PBKDF2)
openssl enc -aes-256-cbc -pbkdf2 -salt -in msg.txt -out msg.enc -pass pass:hunter2
openssl enc -d -aes-256-cbc -pbkdf2 -in msg.enc -out msg.dec -pass pass:hunter2

# ---------- Randomness ----------
openssl rand -hex 16     # 128-bit random value (e.g., an AES key / IV)
openssl rand -base64 32  # 256-bit key, base64
```

**Exercises:**
1. Generate an RSA-2048 and a P-256 key. Compare the on-disk PEM sizes and explain why the EC key is so much smaller for *higher* security.
2. Sign `msg.txt` with ECDSA, flip one byte of the file, and confirm verification fails. Then flip one byte of the *signature* and confirm it also fails.
3. Encrypt the same file twice with AES-256-CBC and a salt. Show the ciphertexts differ. Now reason about what would happen with ECB instead.
4. Produce SHA-256 and SHA3-256 digests of the same input and confirm they differ in value but both change completely on a 1-byte input change (avalanche).
5. Explain in two sentences why reusing the ECDSA nonce `k` across two signatures leaks the private key, and which algorithm (EdDSA) structurally prevents it.
6. Given the equivalence table, state which RSA size matches AES-128 and which ECC curve matches AES-192 — and justify why a CA might still pick RSA-3072 over P-384 for a root.

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why does encryption not provide integrity, and what's the real-world consequence in a protocol like RADIUS or TLS?**
Encryption transforms plaintext to ciphertext but a stream/CTR-style cipher is malleable: an attacker who flips a ciphertext bit flips the corresponding plaintext bit without ever decrypting. So a man-in-the-middle can alter messages undetected unless you add a MAC or use an AEAD mode. This is why TLS records carry an authentication tag, why RADIUS uses the Message-Authenticator (HMAC-MD5) attribute, and why "encrypt-then-MAC" / AEAD (AES-GCM, ChaCha20-Poly1305) is the only safe construction. Conflating "it's encrypted" with "it's tamper-proof" is the single most common junior mistake.

**Q2. A CA still signs certificates with SHA-1. Why is that catastrophic, even though the CA's RSA key is 2048-bit and uncompromised?**
The signature is computed over a hash of the TBSCertificate. If the hash is collision-vulnerable (SHA-1, MD5), an attacker can craft two certificates with the same digest — one benign that the CA happily signs, one malicious. The CA's perfectly strong RSA signature over the benign cert is mathematically valid over the malicious one too, because signatures bind to the *digest*, not the cert bytes. The Flame malware did exactly this with MD5 to impersonate Microsoft Update. Key strength is irrelevant once the hash is broken.

**Q3. What is forward secrecy, and why did static-RSA key transport TLS lose it?**
Forward secrecy means compromise of long-term keys does not retroactively expose past sessions. With static RSA key transport, the client encrypts the premaster secret to the server's long-term public key; anyone who records the traffic and later steals that private key decrypts every captured session. (EC)DHE generates an *ephemeral* key pair per handshake and throws it away — the long-term key only authenticates the exchange, it never encrypts the session secret. So a future key theft yields nothing about past traffic. TLS 1.3 removed static RSA key exchange entirely and mandates ephemeral DH.

**Q4. Why "hash-then-sign" instead of signing the message directly?**
Two reasons. Performance: asymmetric operations can only act on a block roughly the size of the key, so you'd have to chunk a large message — slow and complex. Security: textbook signing of arbitrary messages is malleable and existentially forgeable; signing a fixed-width digest with a sound padding scheme (RSA-PSS, or the hash-into-scalar step of ECDSA/EdDSA) is what's provably secure. In X.509 the CA hashes the TBSCertificate and signs that digest — the `signatureAlgorithm` field names both the hash and the scheme, which is why a weak hash there is fatal.

**Q5. ECC gives equivalent security to RSA at far smaller key sizes — so why hasn't RSA disappeared?**
Inertia and compatibility. Legacy hardware (old smart cards, HSMs), older TLS stacks, and some compliance regimes still assume RSA. Many existing roots are RSA and roots are long-lived (20+ years), so they outlast the technology cycle. ECC also has its own footguns — the ECDSA nonce-reuse private-key leak, and the politically charged history of NIST curve parameters. That said, the trend in modern device onboarding (mobile EAP-TLS certs, IoT) is decisively toward P-256/Ed25519 because of smaller certs, faster handshakes, and lower power.

**Q6. What's the difference between a MAC and a digital signature, and which would you use to protect a RADIUS Access-Request?**
A MAC uses a shared symmetric secret, is fast, but offers no non-repudiation since either party could have produced it; a digital signature uses a private key and gives one-to-many verifiability plus non-repudiation. RADIUS uses a MAC (the HMAC-MD5 Message-Authenticator) because the NAS and the RADIUS server already share a secret and you just need integrity/authenticity per hop, not non-repudiation. Certificates, by contrast, must be verifiable by anyone holding only the CA's public key — so they use signatures. Picking the wrong primitive (e.g., a shared MAC where you needed non-repudiation) is a design-level red flag.

**Q7. Why is a unique, unpredictable nonce/IV so critical, and name two disasters caused by getting it wrong.**
Nonce/IV reuse breaks the security assumptions of the construction. In AES-GCM, reusing a nonce under the same key leaks the GHASH authentication subkey, letting an attacker forge tags — total loss of both confidentiality and integrity. In ECDSA, reusing (or biasing) the per-signature nonce `k` directly leaks the private key via simple algebra. Real disasters: the Sony PlayStation 3 code-signing key was recovered because ECDSA `k` was constant; AES-GCM nonce reuse has broken multiple protocols and VPNs. The Debian OpenSSL entropy bug (2008) made keys themselves predictable. EdDSA derives `k` deterministically to eliminate the ECDSA class of this bug.

**Q8. Why does AES-256 give "only" 128-bit security against a quantum attacker, while RSA-2048 gives essentially zero?**
Grover's algorithm provides a quadratic speedup on unstructured search, halving the effective bits of a symmetric key — so AES-256 drops to ~128-bit effective strength, still comfortably safe. Asymmetric crypto is different: Shor's algorithm solves integer factorization and discrete logs in polynomial time, so a sufficiently large quantum computer breaks RSA, classic DH, and ECC outright — not halved, *demolished*. That's why post-quantum migration focuses on replacing the asymmetric layer (key exchange and signatures) with lattice-based schemes like ML-KEM/ML-DSA, while symmetric crypto just bumps to 256-bit keys.

➡ Next: [Day 02 — PKI Fundamentals & the Trust Model](day-02-pki-fundamentals-trust-model.md)
