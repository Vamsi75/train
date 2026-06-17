# Day 03 — X.509 Certificate Structure

> A certificate is just a signed data structure. To debug EAP-TLS failures, configure SANs correctly, or explain why a cert was rejected, you must read X.509 the way a network engineer reads a packet capture — field by field. Today we crack one open.

## THEORY

### 1. The Big Picture: What an X.509 Cert Is

An X.509 v3 certificate is an **ASN.1-defined structure** with three top-level pieces:

```
Certificate ::= SEQUENCE {
    tbsCertificate       TBSCertificate,      -- the "to-be-signed" body (the actual identity binding)
    signatureAlgorithm   AlgorithmIdentifier, -- algorithm the CA used to sign
    signatureValue       BIT STRING           -- the CA's signature over DER(tbsCertificate)
}
```

The crucial mental model: the CA hashes the **DER encoding of `tbsCertificate`** and signs that digest (Day 01's hash-then-sign). Everything that matters about identity, keys, validity, and extensions lives **inside `tbsCertificate`** — so it's all integrity-protected. Touch one byte and the signature breaks.

> The `signatureAlgorithm` appears **twice** (once inside TBS as `signature`, once outside as the actual algorithm). They must match — a mismatch was historically an attack vector and is now a hard validation check.

### 2. The TBSCertificate Fields

```
TBSCertificate ::= SEQUENCE {
    version              [0] EXPLICIT Version DEFAULT v1,   -- v3 = integer 2
    serialNumber             CertificateSerialNumber,
    signature                AlgorithmIdentifier,           -- must match outer signatureAlgorithm
    issuer                   Name,                          -- DN of the issuing CA
    validity                 Validity,                      -- notBefore / notAfter
    subject                  Name,                          -- DN of the entity (may be empty if SAN present)
    subjectPublicKeyInfo     SubjectPublicKeyInfo,          -- the public key + its algorithm
    issuerUniqueID       [1] IMPLICIT UniqueIdentifier OPTIONAL,  -- deprecated
    subjectUniqueID      [2] IMPLICIT UniqueIdentifier OPTIONAL,  -- deprecated
    extensions           [3] EXPLICIT Extensions OPTIONAL    -- v3 extensions (the interesting part)
}
```

| Field | Meaning / Gotcha |
|-------|------------------|
| **version** | v3 (encoded as integer `2`). v1 had no extensions — you essentially never want v1 except for some legacy roots. |
| **serialNumber** | Unique *per issuing CA*. MUST be a positive integer, **≥ 64 bits of entropy** per CA/B Forum (random serials are a defense against hash-collision cert forgery — see Flame). Not globally unique, only per-CA. |
| **signature** (inner) | Algorithm identifier; must equal the outer `signatureAlgorithm`. |
| **issuer** | The DN of the CA that signed this cert. The chain links because a cert's `issuer` matches the `subject` of its parent (plus AKI/SKI matching). |
| **validity** | `notBefore` / `notAfter`. UTCTime (YYMMDD, years 1950–2049) or GeneralizedTime (≥2050). Expiry is checked at every chain level. |
| **subject** | DN of the entity. For server certs the hostname historically lived in CN here — **now deprecated** (see SAN). May be an **empty DN** when identity is wholly in the SAN. |
| **subjectPublicKeyInfo** | The bound public key + its algorithm (RSA, EC + curve). This is *the* thing being vouched for. |

### 3. ASN.1, DER & OIDs (just enough)

- **ASN.1** (Abstract Syntax Notation One) is the schema language describing the structure. It's abstract — it doesn't say how bytes are laid out.
- **DER** (Distinguished Encoding Rules) is the *canonical* byte encoding used for certs. Canonical = exactly one valid encoding, which is mandatory because you sign the bytes — ambiguity would let two different byte strings hash differently for the "same" cert.
- **BER** is the looser parent of DER; certs must be DER. (PEM is just base64-wrapped DER with `-----BEGIN CERTIFICATE-----` headers — Day 04.)
- Each ASN.1 element is **Tag-Length-Value (TLV)**: a tag byte (type), a length, then the value.
- **OIDs (Object Identifiers)** are dotted-number names for everything — algorithms, extensions, EKU purposes, policies. Examples you should recognize:
  - `2.5.4.3` = commonName (CN)
  - `2.5.29.17` = subjectAltName
  - `2.5.29.19` = basicConstraints
  - `2.5.29.15` = keyUsage
  - `2.5.29.37` = extKeyUsage
  - `1.3.6.1.5.5.7.3.1` = `serverAuth`; `1.3.6.1.5.5.7.3.2` = `clientAuth`
  - `1.3.6.1.4.1.311.20.2.3` = Microsoft UPN (User Principal Name) — **critical for EAP-TLS user mapping**

### 4. The v3 Extensions (and which are *critical*)

Each extension has: an **OID**, a **critical** flag, and a value. The `critical` flag is the rule that **a relying party MUST reject the cert if it doesn't understand a critical extension.** Non-critical unknown extensions may be ignored. Setting criticality wrong is a real interop bug.

**BasicConstraints** (`2.5.29.19`) — *critical on CAs*
- `CA:TRUE` means "this cert may sign other certs." `CA:FALSE` (or absent) = end entity.
- `pathlen:N` caps how many further intermediate CAs may appear below this one (pathlen:0 = may issue only end-entity certs, no sub-CAs).
- **Gotcha:** the legendary 2003 bug where browsers didn't check BasicConstraints — any leaf cert could sign other certs. Always `critical` on CA certs.

**KeyUsage** (`2.5.29.15`) — usually *critical*
- Bit flags for what the **key** may do: `digitalSignature`, `keyEncipherment`, `keyAgreement`, `keyCertSign`, `cRLSign`, `nonRepudiation`, etc.
- CA certs need `keyCertSign` (+ `cRLSign`). TLS server (RSA) needs `digitalSignature` + `keyEncipherment`; (EC)DHE servers need `digitalSignature`. EAP-TLS client cert needs `digitalSignature` (and often `keyAgreement`).

**ExtendedKeyUsage / EKU** (`2.5.29.37`) — refines *purpose*
- `serverAuth` (1.3.6.1.5.5.7.3.1): TLS server.
- `clientAuth` (1.3.6.1.5.5.7.3.2): **TLS/EAP-TLS client — the one that matters for 802.1X.**
- `emailProtection`, `codeSigning`, `OCSPSigning`, Microsoft `Smart Card Logon` (1.3.6.1.4.1.311.20.2.2), etc.
- **EAP-TLS gotcha:** Windows RADIUS (NPS) and most servers *require* the client cert to carry `clientAuth` EKU, and the server cert to carry `serverAuth`. A cert with the wrong EKU is rejected even if everything else is perfect.

**SubjectAlternativeName / SAN** (`2.5.29.17`) — usually non-critical
- Holds the *real* identities: `DNS:`, `IP:`, `email:`/`rfc822Name`, `URI:`, and `otherName` (used for UPN).
- **CN-as-hostname is deprecated.** Since 2017, browsers (Chrome 58+) ignore CN for hostname matching entirely — **only SAN counts.** A server cert with hostname only in CN and no SAN is rejected by modern clients.
- For EAP-TLS *client* certs, the SAN typically carries the user/device identity: `otherName` = **UPN** (`user@domain.com`) and/or `rfc822Name` (email). The RADIUS server maps this SAN value to a directory account.

**AuthorityKeyIdentifier (AKI)** (`2.5.29.35`) & **SubjectKeyIdentifier (SKI)** (`2.5.29.14`)
- SKI = a hash/identifier of *this* cert's public key. AKI = identifier of the *issuer's* key.
- A child's AKI points at its parent's SKI — this is how chain-builders efficiently and unambiguously link certs (especially when a CA has reissued/cross-signed certs with the same DN but different keys). Without these, path-building gets ambiguous fast.

**Authority Information Access (AIA)** (`1.3.6.1.5.5.7.1.1`)
- `caIssuers`: URL to fetch the **issuer's certificate** — lets a client *complete a chain* when the server forgot to send the intermediate (AIA chasing).
- `OCSP`: URL of the OCSP responder for real-time revocation checks.

**CRL Distribution Points (CDP)** (`2.5.29.31`)
- URL(s) where the **Certificate Revocation List** is published. Day 05 covers revocation in depth.

**Certificate Policies** (`2.5.29.32`)
- Carries policy OID(s) linking the cert to a CP/CPS (Day 02). EV certs and federation rely on specific policy OIDs.

> **Critical-vs-non-critical summary:** BasicConstraints and KeyUsage are typically critical; SAN is critical *only* when the subject DN is empty (because then it's the sole identity and must not be ignored); EKU, AIA, CDP, AKI/SKI are typically non-critical.

### 5. EAP-TLS Client Cert vs TLS Server Cert — the Comparison That Matters

| Field / Extension | TLS **Server** cert | EAP-TLS **Client/Device** cert |
|-------------------|---------------------|---------------------------------|
| **EKU** | `serverAuth` (1.3.6.1.5.5.7.3.1) | **`clientAuth`** (1.3.6.1.5.5.7.3.2) |
| **KeyUsage** | `digitalSignature` (+ `keyEncipherment` for RSA kex) | `digitalSignature` (often `+ keyAgreement`) |
| **SAN content** | `DNS:` names (and/or `IP:`) — the hostname(s) | **`otherName`=UPN** (`user@domain`) and/or `rfc822Name` (email) — the *identity*, not a hostname |
| **Subject CN** | Cosmetic only (ignored for matching); use SAN | Often the username/device name (informational) |
| **Who validates it** | The browser/client validates the server | The **RADIUS server** validates the client and maps SAN→directory account |
| **Issued by** | Public CA (web) or private CA | Private CA tied to your IdP (SecureW2 Cloud PKI) |

The single most common EAP-TLS misconfiguration: a cert with `serverAuth` instead of `clientAuth`, or with the user identity in CN but no UPN SAN, so the RADIUS server can't map it to a user. **Get the EKU and SAN right and 80% of EAP-TLS pain disappears.**

## PRACTICE

```bash
# ---------- Generate a key + a self-signed cert with rich extensions ----------
openssl req -x509 -newkey rsa:2048 -keyout leaf.key -nodes -days 365 -out server.pem \
  -subj "/CN=unused/O=SecureW2 Lab" \
  -addext "subjectAltName=DNS:wifi.corp.local,DNS:radius.corp.local" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"

# ---------- The command you will live in: full decode ----------
openssl x509 -in server.pem -text -noout
# Walk the output and locate: Version (3), Serial, Signature Algorithm,
# Issuer, Validity (Not Before/After), Subject, Subject Public Key Info,
# then the X509v3 extensions block (BasicConstraints, KeyUsage, EKU, SAN).

# Pull individual pieces
openssl x509 -in server.pem -noout -serial -subject -issuer -dates
openssl x509 -in server.pem -noout -ext subjectAltName,extendedKeyUsage,basicConstraints
openssl x509 -in server.pem -noout -pubkey            # the bound public key
openssl x509 -in server.pem -noout -fingerprint -sha256

# ---------- Look at the raw ASN.1 / DER (TLV) structure ----------
openssl x509 -in server.pem -outform DER -out server.der
openssl asn1parse -in server.pem                       # see SEQUENCEs, OIDs, the BIT STRING signature
openssl asn1parse -in server.der -inform DER | head -40

# ---------- Decode an OID you see in asn1parse ----------
# e.g. 1.3.6.1.5.5.7.3.2 -> clientAuth ; 2.5.29.17 -> subjectAltName

# ---------- Craft a config file for an EAP-TLS CLIENT cert (UPN SAN) ----------
cat > client_eap.cnf <<'EOF'
[ req ]
distinguished_name = dn
req_extensions     = v3_client
prompt             = no

[ dn ]
CN = vamsi.h
O  = SecureW2 Lab

[ v3_client ]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature,keyAgreement
extendedKeyUsage       = clientAuth
subjectAltName         = @san

[ san ]
# UPN goes in otherName with the Microsoft UPN OID 1.3.6.1.4.1.311.20.2.3
otherName = 1.3.6.1.4.1.311.20.2.3;UTF8:vamsi.h@corp.local
email     = vamsi.h@corp.local
EOF

# Generate the client key + CSR carrying those extensions
openssl req -new -newkey rsa:2048 -nodes -keyout client.key -out client.csr -config client_eap.cnf
# Confirm the CSR carries clientAuth EKU and the UPN SAN
openssl req -in client.csr -noout -text | grep -A4 -Ei "Extended Key Usage|Alternative Name"
```

**Exercises:**
1. Run `openssl x509 -text -noout` on the generated server cert and write down, in order, every TBSCertificate field. Identify which extensions are marked `critical` and explain why each is or isn't.
2. Generate the EAP-TLS *client* CSR from `client_eap.cnf`. Prove via `openssl req -text` that it carries `clientAuth` EKU and a UPN `otherName` SAN. Then change the EKU to `serverAuth` and explain why NPS/RADIUS would reject it as a client cert.
3. Create a server cert whose hostname is *only* in the CN (no SAN). Reason about why Chrome would reject it, and confirm with `openssl x509 -ext subjectAltName` that no SAN is present.
4. Use `openssl asn1parse` on the DER form and locate: the version integer (2), the OID for `subjectAltName` (2.5.29.17), and the final `BIT STRING` that is the CA signature.
5. Generate two certs and compare their serial numbers. Explain (referencing Flame) why CAs are required to use ≥64 bits of random entropy in serials.
6. Add `basicConstraints=critical,CA:TRUE,pathlen:0` to a cert and explain what that cert is now allowed (and not allowed) to sign.

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why is the hostname in the CN deprecated, and what exactly replaced it?**
The CN is a free-form, single-valued DN attribute never designed to hold network identifiers, and historically it caused ambiguity (is "wifi.corp" a CN or a real name?) and supported only one name. The **SubjectAlternativeName** extension replaced it: it's purpose-built, multi-valued, typed (`DNS`, `IP`, `email`, `otherName`), and unambiguous. Since Chrome 58 (2017) and modern stacks, **CN is ignored entirely for hostname matching — only SAN is consulted.** A cert with the hostname solely in CN and no SAN fails on modern clients, which is a classic "but it worked years ago" debugging trap.

**Q2. What does the `critical` flag on an extension actually do, and give a real consequence of getting it wrong.**
A relying party MUST reject a certificate if it encounters a **critical** extension whose OID it does not understand; unknown **non-critical** extensions may be safely ignored. So criticality is a forward-compatibility and safety control. Get it wrong in either direction and you have a bug: mark a niche extension critical and older clients that don't know it will reject otherwise-valid certs; mark BasicConstraints non-critical (or omit it) and you risk the historic class of bug where a leaf cert was wrongly treated as a CA. BasicConstraints and KeyUsage on CAs should be critical for exactly this reason.

**Q3. How does a client build and link a certificate chain — what fields connect a child to its parent?**
Two mechanisms. The name-based link: a cert's **issuer DN** equals its parent's **subject DN**. The key-based link, which is more robust: the child's **AuthorityKeyIdentifier (AKI)** matches the parent's **SubjectKeyIdentifier (SKI)**. The key-based link disambiguates the common real-world case where one CA DN has multiple certificates (renewed or cross-signed with different keys) — name matching alone would be ambiguous, but AKI→SKI points at the exact issuing key. If the server didn't send the intermediate, the client can use the **AIA caIssuers** URL to fetch it and complete the chain.

**Q4. Precisely how does an EAP-TLS client cert differ from a TLS server cert?**
Three things matter. **EKU:** client cert carries `clientAuth` (1.3.6.1.5.5.7.3.2), server cert carries `serverAuth` (1.3.6.1.5.5.7.3.1) — RADIUS servers like NPS enforce this. **SAN content:** a server cert's SAN holds `DNS`/`IP` hostnames for name matching; a client cert's SAN holds an **identity** — typically a UPN in `otherName` (OID 1.3.6.1.4.1.311.20.2.3) and/or `rfc822Name` email — which the RADIUS server maps to a directory account. **Who validates it:** the server cert is validated by the connecting client for the hostname; the client cert is validated by the RADIUS server and mapped to a user. Same X.509 format, opposite roles.

**Q5. Why must certificates be DER-encoded specifically, and not just any ASN.1 encoding?**
Because the signature is computed over the *bytes* of the encoded `tbsCertificate`. DER is the **canonical** encoding — exactly one valid byte representation for a given structure. If the looser BER were allowed, the same logical cert could have multiple byte encodings hashing to different digests, breaking verification and opening room for ambiguity/forgery games. Canonical encoding guarantees that everyone hashes the identical bytes and gets the identical signature input. (PEM is merely base64-wrapped DER for transport, not a different encoding of the structure.)

**Q6. Why are CAs required to put substantial random entropy in the serial number?**
The serial number is part of the to-be-signed body, so its bytes feed the hash that the CA signs. If serials were sequential/predictable, an attacker mounting a hash-collision attack (as Flame did against MD5) has more freedom to engineer two certificates that collide. Forcing ≥64 bits of unpredictable entropy into the serial injects randomness the attacker can't control into the signed structure, dramatically raising the bar for collision-based forgery. It's a cheap, structural defense-in-depth measure mandated by the CA/Browser Forum after real attacks.

**Q7. An EAP-TLS auth fails: server logs say the client cert is valid and trusted, but the user "can't be found." Where do you look?**
This is almost always a **SAN-to-identity mapping** problem, not a trust problem. The cert chains and is in date, but the RADIUS server couldn't map its SAN to a directory account — the cert lacks the expected UPN `otherName` (or has the identity only in CN), or the UPN value doesn't match the account in AD/Entra, or the server is configured to map on a different field (email vs UPN vs SAN DNS). Inspect the client cert's SAN (`openssl x509 -ext subjectAltName`), confirm it carries the UPN OID `1.3.6.1.4.1.311.20.2.3`, and check the RADIUS/NPS name-mapping policy. Trust validity and identity mapping are two separate checks.

**Q8. What is `pathlen` in BasicConstraints and why does it matter for a private enterprise PKI?**
`pathlen:N` on a CA certificate limits how many additional CA certificates may appear *below* it in a chain — `pathlen:0` means the CA may issue only end-entity certificates, not further sub-CAs. It's a containment control: it stops an issuing CA from minting rogue intermediate CAs, bounding the damage if that CA is compromised. In an enterprise PKI you typically set `pathlen:0` on your issuing CA so it can sign device/user leaf certs but never spawn another CA layer, keeping the hierarchy shallow, auditable, and harder to abuse. Combined with name constraints, it tightly scopes what an intermediate can do.

➡ Next: [Day 04 — Encoding Formats & PKCS Standards](day-04-encoding-formats-pkcs.md)
