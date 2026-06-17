# Day 12 — TLS Handshake Deep Dive & Mutual TLS

> "If you understand the TLS handshake, you already understand 80% of EAP-TLS. The other 20% is just packaging it inside 802.1X." Internalize this file and the RADIUS/EAP days later become trivial.

---

## THEORY

### 1. What TLS actually does (and the three goals)

TLS (Transport Layer Security, the successor to SSL) gives you three things over an untrusted network:

| Goal | Mechanism |
|------|-----------|
| **Confidentiality** | Symmetric encryption (AES-GCM, ChaCha20-Poly1305) of the data after the handshake. |
| **Integrity** | AEAD tag / HMAC — tampering is detected. |
| **Authentication** | X.509 certificates verified against a trust anchor. Server is *always* authenticated; client is *optionally* authenticated (that "optional" piece is mTLS). |

The genius of TLS is the **hybrid model**: asymmetric crypto (slow, certificate-based) is used *only* to authenticate and to agree on a shared secret. Bulk data then uses fast symmetric crypto with keys derived from that secret. The handshake is the negotiation phase; the record layer is the bulk-transfer phase.

### 2. TLS 1.2 full handshake — step by step

This is the classic 2-RTT (two round-trip) handshake. Memorize the message order; interviewers love asking "what comes after ServerHello?"

```text
CLIENT                                                 SERVER
  |  ---------------- ClientHello ----------------->     |   (1)
  |                                                       |
  |  <--------------- ServerHello ------------------      |   (2)
  |  <--------------- Certificate ------------------      |   (3)
  |  <--------------- ServerKeyExchange ------------       |   (4)  (for ECDHE)
  |  <--------------- CertificateRequest -----------      |   (4b) (only if mTLS)
  |  <--------------- ServerHelloDone --------------      |   (5)
  |                                                       |
  |  ----------------- Certificate ----------------->     |   (6)  (only if mTLS)
  |  ------------- ClientKeyExchange ---------------->     |   (7)
  |  ------------- CertificateVerify ---------------->     |   (8)  (only if mTLS)
  |  ------------- [ChangeCipherSpec] -------------->      |   (9)
  |  ----------------- Finished -------------------->      |   (10)
  |                                                       |
  |  <----------- [ChangeCipherSpec] ---------------      |   (11)
  |  <---------------- Finished ---------------------      |   (12)
  |                                                       |
  |  <============== Application Data ==============>      |   (encrypted)
```

**(1) ClientHello** — the client opens by advertising:
- Highest TLS version it supports.
- A 32-byte **client random** (28 bytes random + historically 4 bytes timestamp).
- A list of **cipher suites** it supports, in preference order.
- Extensions: **SNI** (Server Name Indication — which hostname I want, critical for shared-IP virtual hosts), supported elliptic curves, signature algorithms, ALPN (h2/http1.1), etc.

**(2) ServerHello** — the server *chooses*:
- The TLS version (lowest of "what client offered" and "what I support").
- A 32-byte **server random**.
- **One** cipher suite from the client's list (server has final say — server preference usually wins). This single line, e.g. `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`, decides key exchange (ECDHE), authentication (RSA cert), bulk cipher (AES-256-GCM), and PRF hash (SHA384).
- A session ID for resumption.

**(3) Certificate** — server sends its leaf cert plus intermediate(s). **Gotcha:** the server should send the full chain *except* the root (the client already trusts the root). Missing intermediates is the #1 cause of "works in browser, fails in curl/Java" — browsers cache/AIA-fetch intermediates, strict clients don't.

**(4) ServerKeyExchange** — for **ECDHE** (the modern default), the server generates an ephemeral EC key pair, sends its **ephemeral public key + the named curve**, and **signs** all of it (client random + server random + params) with the **private key of its certificate**. This signature is what actually proves the server owns the cert — not the certificate itself. (With legacy RSA key transport there is *no* ServerKeyExchange; see §4.)

**(5) ServerHelloDone** — "I'm done talking, your turn."

**(7) ClientKeyExchange** — client generates *its* ephemeral EC key pair and sends its ephemeral public key. Now both sides do ECDH(my-ephemeral-private, their-ephemeral-public) → identical **pre-master secret**. No secret ever crosses the wire.

**Key derivation:** `master_secret = PRF(pre_master_secret, "master secret", client_random + server_random)`. From the master secret both sides derive the symmetric encryption keys, MAC keys, and IVs.

**(9) ChangeCipherSpec** — "everything after this is encrypted with the new keys."

**(10/12) Finished** — a hash/PRF over the *entire handshake transcript*, encrypted with the new keys. If an attacker tampered with any earlier (plaintext) handshake message, the Finished hashes won't match and the connection aborts. This is the handshake's self-healing integrity check.

### 3. ECDHE and why PFS matters

**PFS (Perfect Forward Secrecy)** = compromise of the server's long-term private key does **not** let an attacker decrypt past captured sessions.

- With **ECDHE** (Ephemeral), a fresh key pair is generated per handshake and thrown away. The session key is derived from ephemeral keys; the cert key only *signs*, it never *encrypts* the secret. Steal the cert key tomorrow → yesterday's traffic stays safe. 
- With **legacy RSA key transport** (no PFS), the client encrypts the pre-master secret with the server's RSA public key. Anyone who later steals the RSA private key + has a packet capture can decrypt everything retroactively. This is why RSA key exchange is dead.

`ECDHE` = key agreement, `RSA`/`ECDSA` (in the suite name) = the signature/cert type. Don't conflate them.

### 4. TLS 1.3 — what changed and why it matters

TLS 1.3 (RFC 8446) is a redesign, not a tweak:

- **1-RTT handshake.** The client *guesses* the key-share in its ClientHello (sends an ECDHE public key immediately). Server responds with its key-share in ServerHello and the rest of the handshake is **already encrypted**. App data flows after one round trip.
- **Encrypted handshake.** Certificate, CertificateVerify, Finished — all encrypted. An eavesdropper can't even see the server cert (helps privacy; SNI is still cleartext unless ECH).
- **RSA key transport removed.** Only (EC)DHE. **PFS is mandatory** — you cannot configure a non-PFS suite.
- **Cipher suites simplified.** A 1.3 suite only names the AEAD + hash, e.g. `TLS_AES_256_GCM_SHA384`. Key exchange and signature are negotiated in separate extensions.
- **Removed legacy junk:** static RSA, static DH, CBC-mode ciphers, RC4, MD5/SHA1 signatures, compression, renegotiation.
- **0-RTT (early data).** On resumption, the client can send app data in the very first flight using a PSK. **Gotcha:** 0-RTT data is **replayable** — an attacker can capture and resend it. Never put non-idempotent requests (e.g. "transfer money") in 0-RTT.

```text
TLS 1.3 (1-RTT):
CLIENT                                          SERVER
  | -- ClientHello (+key_share) ------------->    |
  | <- ServerHello (+key_share) {EncryptedExt,    |
  |        Certificate, CertVerify, Finished}     |
  | -- {Finished} -------------------------->     |
  | <======== Application Data ==========>        |
   { } = encrypted
```

### 5. How the client validates the server certificate

A handshake "succeeding" cryptographically is meaningless if the cert is wrong. The client (browser, OS, supplicant) runs **path validation**:

1. **Chain building & signature verification** — leaf signed by intermediate, intermediate signed by root, root in the local **trust store**. Each signature is verified.
2. **Trust anchor** — the chain must terminate at a CA the client explicitly trusts.
3. **Validity period** — `notBefore`/`notAfter` on *every* cert in the chain must cover "now". Expired intermediate breaks everything below it.
4. **Hostname / SAN match** — the requested hostname (and SNI) must appear in the leaf cert's **Subject Alternative Name**. CN-only matching is deprecated and ignored by modern clients.
5. **Key usage / EKU** — leaf must have `serverAuth` EKU; CA certs must have `cA:TRUE` basic constraints.
6. **Revocation** — CRL or OCSP (ideally **OCSP stapling**, where the server attaches a fresh signed OCSP response so the client doesn't have to call the CA). Covered in depth on the CRL/OCSP day.

Any single failure → handshake aborts with a TLS alert (`bad_certificate`, `certificate_expired`, `unknown_ca`, etc.).

### 6. Session resumption

Full handshakes are expensive. Resumption skips the asymmetric work:
- **TLS 1.2 Session IDs** — server stores session state, client presents the ID. Stateful on the server.
- **TLS 1.2 Session Tickets** (RFC 5077) — server encrypts the session state and hands it to the client as an opaque blob; client presents it next time. Stateless on the server.
- **TLS 1.3 PSK resumption** — after a handshake the server issues a `NewSessionTicket`; resumption uses that as a Pre-Shared Key. 0-RTT rides on this. **Gotcha:** poorly rotated ticket keys break PFS for resumed sessions — rotate them frequently.

### 7. Mutual TLS (mTLS) — the client proves itself too

In ordinary TLS only the server authenticates. In **mTLS** the server *also* demands the client present a certificate.

- Server sends **CertificateRequest** (with acceptable CA names + signature algorithms).
- Client sends its **Certificate** (the client/leaf cert).
- Client sends **CertificateVerify**: it **signs the handshake transcript with its certificate's private key**. This is the proof of possession — anyone can copy a public cert, but only the legitimate holder can produce a valid signature with the matching private key. **This message is the crux of mTLS.**
- The server then path-validates the client cert exactly like the client validated the server's (chain, validity, revocation, and usually a check that the identity maps to a known account).

Where mTLS is used:
- **Service-to-service / API auth** in zero-trust architectures (no bearer tokens to steal; identity is the cert).
- **Service meshes** (Istio/Linkerd) — sidecars mTLS each other automatically.
- **EAP-TLS** — and this is the one that matters for us.

### 8. The bridge: EAP-TLS = mutual TLS carried over 802.1X

This is the single most important conceptual link in this whole repo:

> **EAP-TLS is just a mutual-TLS handshake whose messages are chopped into EAP packets and tunneled across 802.1X / RADIUS instead of over a TCP socket.**

- The **supplicant** (laptop/phone) plays the **TLS client** and presents a **client certificate** → mutual auth.
- The **RADIUS server** (e.g. SecureW2 Cloud RADIUS) plays the **TLS server** and presents a **server cert**; it also issues the `CertificateRequest`.
- The same ClientHello → ServerHello → Certificate → CertificateVerify → Finished flow happens — but each TLS record is encapsulated in `EAP-TLS` fragments, ferried by the authenticator (switch/AP) inside RADIUS `Access-Challenge`/`Access-Request` packets.
- No password is ever sent. The user's identity is the certificate. That is why cert-based Wi-Fi/802.1X is phishing-resistant — there is no shared secret a user can be tricked into revealing.

So when SecureW2 says "passwordless, certificate-based network authentication," they mean: **EAP-TLS mutual auth, where every device and user gets an X.509 cert from a managed PKI, and Cloud RADIUS terminates the TLS server side.** Everything you learn here about CertificateVerify, chain validation, and PFS applies directly.

### 9. Common handshake failures (and the real cause)

| Symptom / Alert | Real cause |
|-----------------|-----------|
| `certificate_unknown` / `unknown_ca` | Client doesn't trust the issuing CA, or server didn't send intermediates. |
| `certificate_expired` | Leaf **or** an intermediate is outside its validity window. |
| Hostname mismatch | SAN doesn't list the requested name; or SNI not sent / wrong. |
| `handshake_failure` (no shared cipher) | No overlap between client and server cipher suites / TLS versions. |
| `bad_certificate` in mTLS | Client cert missing, untrusted, expired, or `CertificateVerify` signature failed. |
| Works in browser, fails in CLI/Java | Missing intermediate chain (browsers fetch via AIA, strict clients don't). |
| EAP-TLS fails but everything "looks right" | Time skew on supplicant breaks validity check; or NAS can't fragment large cert chains (RADIUS framed-MTU). |

---

## PRACTICE

> You need `openssl` (1.1.1+ or 3.x). All commands run in `bash`.

### Inspect a real server handshake

```bash
# Full handshake against a public host; -servername sets SNI (essential!)
openssl s_client -connect example.com:443 -servername example.com

# Show the certificate chain the server actually presents, and verify it
openssl s_client -connect example.com:443 -servername example.com \
  -showcerts < /dev/null 2>/dev/null

# Just the negotiated protocol + cipher (grep the summary)
openssl s_client -connect example.com:443 -servername example.com < /dev/null 2>/dev/null \
  | grep -E "Protocol|Cipher|Verify"
```

### Force a TLS version or cipher (prove negotiation)

```bash
# Force TLS 1.2 only
openssl s_client -connect example.com:443 -servername example.com -tls1_2 < /dev/null

# Force TLS 1.3 only
openssl s_client -connect example.com:443 -servername example.com -tls1_3 < /dev/null

# Try a deliberately unsupported version to see the failure
openssl s_client -connect example.com:443 -tls1_1 < /dev/null   # expect handshake_failure

# Offer only one TLS 1.2 cipher suite (tests server support)
openssl s_client -connect example.com:443 -servername example.com \
  -cipher 'ECDHE-RSA-AES256-GCM-SHA384' -tls1_2 < /dev/null

# TLS 1.3 ciphersuites use a different flag
openssl s_client -connect example.com:443 -servername example.com \
  -ciphersuites TLS_AES_256_GCM_SHA384 -tls1_3 < /dev/null
```

### Validate a cert's hostname / dates / SAN

```bash
# Pull the leaf cert and read its guts
openssl s_client -connect example.com:443 -servername example.com < /dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# Ask openssl to enforce hostname verification (fails loudly on mismatch)
openssl s_client -connect example.com:443 -servername example.com \
  -verify_hostname example.com < /dev/null
```

### Build a tiny mTLS lab (server requires a client cert)

```bash
# --- 1. Make a throwaway CA ---
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
  -subj "/CN=Lab-CA" -days 3650

# --- 2. Server cert signed by the CA (SAN = localhost) ---
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 365 -copy_extensions copyall

# --- 3. Client cert signed by the same CA ---
openssl req -newkey rsa:2048 -nodes -keyout client.key -out client.csr \
  -subj "/CN=alice@lab"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -days 365

# --- 4. Start an mTLS server. -Verify 1 + -verifyCAfile => REQUIRE client cert ---
openssl s_server -accept 4433 -cert server.crt -key server.key \
  -CAfile ca.crt -Verify 1 -tls1_2
#   -verify  = ask for client cert but continue if absent (optional mTLS)
#   -Verify  = FAIL the handshake if no/invalid client cert (mandatory mTLS)
```

```bash
# --- 5. In a second terminal: connect WITH a client cert (succeeds) ---
openssl s_client -connect localhost:4433 \
  -cert client.crt -key client.key -CAfile ca.crt -servername localhost

# --- 6. Connect WITHOUT a client cert (server -Verify rejects it) ---
openssl s_client -connect localhost:4433 -CAfile ca.crt -servername localhost
#   => expect: "peer did not return a certificate" / handshake aborts
```

### Read the handshake at the wire level

```bash
# -msg dumps every handshake message; -state shows the state machine
openssl s_client -connect localhost:4433 -cert client.crt -key client.key \
  -CAfile ca.crt -msg -state < /dev/null

# Look for these lines in order: ClientHello, ServerHello, Certificate,
# CertificateRequest, ServerHelloDone, Certificate (client), ClientKeyExchange,
# CertificateVerify, Finished.  The CertificateVerify proves client key possession.
```

**Exercises:**
1. Capture a TLS 1.2 handshake with `-msg` and label every message against the diagram in §2. Identify exactly where `CertificateVerify` appears and explain what it signs.
2. Connect to the same host with `-tls1_2` then `-tls1_3`. Diff the message list — confirm that in 1.3 the Certificate is *not* visible in cleartext.
3. In your mTLS lab, set a client cert's clock invalid by issuing one with `-days -1` (already expired) and watch the server reject it. Map the alert to the table in §9.
4. Stop sending the intermediate from a server chain (or use `badssl.com` test endpoints) and reproduce the "works in browser, fails in CLI" missing-intermediate failure.
5. **Bridge exercise:** Write one paragraph mapping each mTLS message (ClientHello, server Certificate, CertificateRequest, client Certificate, CertificateVerify) to its role in EAP-TLS — who is the TLS client, who is the TLS server, and what carries the bytes.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. In TLS 1.2 with ECDHE-RSA, what does the RSA private key actually do — does it encrypt the session key?**
No. With ECDHE the RSA (or ECDSA) key is used **only to sign** the ServerKeyExchange (the ephemeral DH parameters + randoms). The session key comes from the ephemeral ECDH exchange. The cert key proves *identity*; it never transports the secret. This is precisely why ECDHE gives PFS while legacy RSA key transport does not.

**Q2. Why is RSA key transport removed in TLS 1.3?**
Because it has no forward secrecy: the client encrypts the pre-master secret with the server's static RSA public key, so anyone who later obtains that private key plus a packet capture can decrypt all past sessions. TLS 1.3 mandates (EC)DHE so every session has independent, ephemeral key material.

**Q3. What stops a man-in-the-middle from tampering with the cleartext ClientHello/ServerHello in TLS 1.2?**
The **Finished** messages. Each side computes a PRF/hash over the *entire* handshake transcript and sends it encrypted under the freshly derived keys. If an attacker altered any earlier message, the two transcripts diverge, the Finished verification fails, and the connection aborts before any app data flows.

**Q4. What exactly proves the client owns its private key in mTLS, and why isn't sending the certificate enough?**
A certificate is public — anyone can copy it. The proof is **CertificateVerify**: the client signs the handshake transcript with the private key matching its cert. Only the legitimate key holder can produce a signature the server can verify against the cert's public key. Without CertificateVerify, mTLS would authenticate nothing.

**Q5. Explain how EAP-TLS relates to the TLS handshake you just described.**
EAP-TLS *is* a mutual-TLS handshake. The supplicant is the TLS client (presenting a client cert), the RADIUS server is the TLS server (presenting a server cert and sending CertificateRequest), and the exact same message flow — including CertificateVerify and Finished — occurs. The difference is purely transport: TLS records are fragmented into EAP-TLS packets and carried over 802.1X between supplicant and authenticator, then over RADIUS between authenticator and server. Same crypto, different envelope.

**Q6. A user says "my Wi-Fi auth fails only on this one laptop, certs look fine." What TLS-level cause should you suspect first?**
**Clock skew.** Certificate path validation checks `notBefore`/`notAfter`. If the laptop's clock is wrong, an otherwise valid client or server cert appears expired or not-yet-valid, and the EAP-TLS handshake aborts during validation — even though the cert files are perfectly correct. (Runner-up: a too-small RADIUS framed-MTU fragmenting the cert chain badly.)

**Q7. What's the security risk of TLS 1.3 0-RTT data, and how do you mitigate it?**
0-RTT (early data) is sent before the handshake completes using a resumption PSK, so it has **no replay protection** — an attacker can capture and resend it. Mitigation: only allow 0-RTT for **idempotent, safe** requests (e.g. GET), enforce single-use tickets / anti-replay windows at the server, and never carry state-changing operations in early data.

**Q8. Server cert is valid and trusted, browser is happy, but a Java client throws `unable to find valid certification path`. Why?**
Almost always a **missing intermediate** in the server's chain. Browsers fill the gap via cached intermediates or AIA fetching; strict clients (Java, curl, Go) build the chain only from what the server sends plus their trust store. Fix the server to present leaf + all intermediates (everything except the root).

**Q9. What is SNI, why is it sent in cleartext, and what fixes that?**
SNI (Server Name Indication) tells the server which hostname/virtual host the client wants so the right certificate is served on a shared IP. It's in the cleartext ClientHello (the server needs it *before* it can pick a cert), which leaks the destination hostname to eavesdroppers. **Encrypted Client Hello (ECH)** encrypts SNI using a public key published in DNS, closing that gap.

---

➡ Next: [Day 13 — AAA Model & RADIUS Fundamentals](day-13-aaa-radius-fundamentals.md)
