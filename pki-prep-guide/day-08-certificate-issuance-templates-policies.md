# Day 08 — Issuance, Templates & Certificate Policies

By now you understand keys, CSRs, X.509 structure and trust chains. Today we answer the operational question that actually matters in production PKI: **when a request arrives, how does a CA decide *what kind* of certificate to mint, with *which* fields, for *whom*, and *for how long*?** The answer is templates (a.k.a. profiles) governed by a certificate policy. Get this wrong and you ship a Wi-Fi client cert that a browser happily accepts as a TLS server cert — a real privilege-escalation footgun.

---

## THEORY

### 1. The issuance flow — request → RA validation → CA signing → delivery

Every issuance, whether a public CA or a SecureW2 JoinNow managed CA, walks the same five stations:

```
  Subject/Device                RA (Registration Authority)        CA (Certificate Authority)
 ┌──────────────┐   CSR + proof  ┌────────────────────────┐  approved  ┌──────────────────────┐
 │ keypair gen  │ ─────────────► │ identity validation    │ ─────────► │ apply template       │
 │ build CSR    │                │ template selection     │            │ sign with CA key     │
 └──────────────┘                │ policy enforcement     │            │ assign serial + AKI  │
        ▲                        └────────────────────────┘            └──────────┬───────────┘
        │  cert + chain (delivery)                                                │
        └─────────────────────────────────────────────────────────────────────-─┘
```

1. **Request** — the subject generates a keypair (private key never leaves the device, ideally TPM/Secure Enclave-bound) and builds a CSR carrying the public key plus *requested* attributes.
2. **RA validation** — the RA authenticates the requester and decides *who they are* and *what they're allowed to get*. This is the trust-anchoring step. The RA never holds the CA signing key.
3. **Template selection** — based on the validated identity and request context, the RA picks a profile (Wi-Fi client vs TLS server vs user/UPN).
4. **CA signing** — the CA applies the template's fixed fields, **overwrites or ignores** attacker-controllable CSR fields, assigns a unique serial, and signs.
5. **Delivery** — cert + full chain returned (PKCS#7/PKCS#12, SCEP/EST/ACME response, or pushed via MDM).

> **Gotcha #1 — the CSR is a *request*, not an order.** A CSR can ask for `CA:TRUE`, `serverAuth`, a SAN of `login.microsoft.com`, anything. The CA's job is to **ignore the dangerous parts** and stamp authoritative values from the template. Any CA that blindly copies CSR extensions is broken. Treat every CSR field as untrusted input.

### 2. Templates / profiles — what a profile pins down

A **template** (Microsoft AD CS term) / **profile** (most other PKIs, RFC 3647 language) is the recipe that locks down the variable parts of a certificate. A profile fixes:

| Knob | Why it matters |
|---|---|
| **Validity period** | TLS server short (≤398/90d), device certs longer with auto-renew, root 10–20y |
| **Key constraints** | min RSA 2048/3072 or EC P-256/P-384; reject weak/wrong algorithms |
| **Basic Constraints** | `CA:FALSE` for all leafs — non-negotiable |
| **Key Usage (KU)** | `digitalSignature` + `keyEncipherment` for TLS; `digitalSignature` for EAP client |
| **Extended Key Usage (EKU)** | THE field that separates a Wi-Fi client cert from a web server cert |
| **Subject / SAN rules** | what DN, which SAN types, where they come from |
| **Policy OIDs** | which certificate policy this cert asserts |
| **CRL/OCSP/AIA URLs** | revocation + chain-building pointers |
| **Renewal behavior** | rekey vs reuse, overlap window |

#### Three canonical profiles, side by side

| Field | **TLS server** | **Wi-Fi / EAP-TLS client** | **User / UPN (smartcard-style)** |
|---|---|---|---|
| Basic Constraints | `CA:FALSE` | `CA:FALSE` | `CA:FALSE` |
| Key Usage | `digitalSignature, keyEncipherment` | `digitalSignature` | `digitalSignature` |
| **EKU** | **`serverAuth` (1.3.6.1.5.5.7.3.1)** | **`clientAuth` (1.3.6.1.5.5.7.3.2)** | **`clientAuth` + `1.3.6.1.4.1.311.20.2.2` (Smart Card Logon)** |
| Subject CN | FQDN (`vpn.corp.example`) | device id / user (often cosmetic) | user display name |
| SAN | `DNS:vpn.corp.example` (+ SANs) | `DNS`/`otherName` device id | `otherName:UPN=user@corp.com`, `rfc822Name:user@corp.com` |
| Validity | 90–398 days | 1–3 years (auto-renewed) | aligned to user lifecycle |
| Min key | EC P-256 / RSA 2048 | EC P-256 | EC P-256 / RSA 2048 |

> **Gotcha #2 — EKU is a security boundary, not metadata.** A relying party MUST check EKU. A NPS/RADIUS server validating EAP-TLS requires `clientAuth`; a browser requires `serverAuth` for the host it's connecting to. Issue a cert with *both* and you've built a confused-deputy credential. Keep EKUs minimal and purpose-specific.

> **Gotcha #3 — UPN goes in the SAN `otherName`, not the CN.** Modern EAP-TLS/802.1X identity matching (and Windows smart-card logon) reads `otherName` with OID `1.3.6.1.4.1.311.20.2.2` (Microsoft UPN) or `rfc822Name`. The CN is increasingly ignored. After CA/B Forum deprecation of CN-as-identity for TLS, **SAN is the only field that matters** for name validation.

### 3. Identity validation levels — public DV/OV/EV vs internal trust-by-policy

Public CAs sell three validation tiers — the difference is *how hard the RA worked*, not crypto:

- **DV (Domain Validated)** — prove control of the domain (ACME HTTP-01/DNS-01). Automated, seconds. No org identity. This is 99% of web TLS today.
- **OV (Organization Validated)** — DV + vetted legal organization (subject `O=`). Human review.
- **EV (Extended Validation)** — strict CA/B Forum vetting of legal entity. The old "green bar." Browsers no longer surface it specially.

For **internal/enterprise PKI** (SecureW2, AD CS), the concept inverts: there is no public "validation level." Trust comes from **policy + a strong RA authentication step**. The "validation" is: *did the requester prove they are an authorized identity in our IdP before we minted them a cert?* That proof is the SAML/OIDC/SCIM tie-in (next section). Internal certs are typically **OV-equivalent by construction** — you control the namespace and the enrollment gate.

> **Gotcha #4 — DV proves domain control, not who you are.** A DV cert for `paypa1.com` is perfectly valid. Validation level ≠ trustworthiness of the operator. This is why phishing-resistant client auth relies on *internal* RA-vetted identity, not public DV.

### 4. Attribute mapping — from an IdP into the certificate

This is the SecureW2 heart of the matter. The client never gets to *self-assert* its identity into the cert — the RA pulls authoritative attributes from the IdP and injects them.

```
 Entra ID / Okta / Google Workspace
        │  (SAML assertion / OIDC id_token / SCIM)
        ▼
   JoinNow RA  ── reads claims ──►  attribute mapping policy
        │            UPN, mail, groups, deviceId, dept
        ▼
   CA mints cert with:
        SAN otherName = UPN claim
        SAN rfc822Name = mail claim
        Subject OU     = department claim
        custom OID ext = group/role (dynamic policy)
```

Mapping patterns:

- **SAN = UPN** — `userPrincipalName` from Entra → `otherName(1.3.6.1.4.1.311.20.2.2)`. This is what RADIUS matches on for EAP-TLS.
- **SAN = email** — `mail`/`email` claim → `rfc822Name`. Used for S/MIME and some 802.1X policies.
- **Custom OIDs** — encode `department`, `employeeType`, `groups` into a private-arc OID extension so the RADIUS server can make **authorization** decisions (VLAN assignment) straight from the cert, no live IdP lookup at auth time.
- **Dynamic policy** — group membership at enrollment selects the *template* (contractor → short-lived restricted cert; full-time → standard) and stamps the right policy OID.

> **Gotcha #5 — bind to attributes that are stable and authoritative.** Mapping SAN to a mutable display name breaks renewal and RADIUS matching when the user renames. UPN/immutableID/objectGUID are the safe anchors. And if you bake group claims into the cert (custom OID), remember the cert is now a **point-in-time snapshot** — revoke/reissue when the user changes role, or pair with live lookup.

### 5. CP / CPS and certificate policy OIDs

- **CP (Certificate Policy)** — *what* the PKI promises: validation rigor, key sizes, allowed uses, liability. A named set of rules, identified by a **policy OID** that gets stamped into the `certificatePolicies` extension.
- **CPS (Certification Practice Statement)** — *how* the CA operationally fulfills the CP: HSM handling, RA procedures, audit, key ceremonies. RFC 3647 defines the shared outline for both.
- **Policy OID** — e.g. `2.16.840.1.114412.x.x.x`. A relying party can require a specific policy OID before trusting a cert (`certificatePolicies` + path-validation policy mapping). `2.5.29.32.0` (anyPolicy) is the wildcard.

> **Gotcha #6 — the policy OID is machine-enforceable trust.** Sophisticated relying parties pin policy OIDs so a generic cert from the same CA can't be reused in a high-assurance context. In SecureW2 deployments you assert a private policy OID so downstream systems can distinguish "JoinNow-issued, IdP-vetted device cert" from anything else.

### 6. Separation of duties — RA vs CA

The cardinal rule: **the entity that decides *who gets a cert* must not be the entity that *holds the signing key*.**

- **RA** = identity + authorization. Authenticates requesters, enforces template/policy selection. No private key power.
- **CA** = the signing oracle. Holds the key (in an HSM), signs whatever the RA approves, enforces template floor/ceiling, owns serials and CRL/OCSP.

Why: it limits blast radius. A compromised RA can mis-authorize but cannot forge; a compromised CA is catastrophic and is therefore air-gapped/HSM-protected and minimally exposed. In SecureW2's managed model, the cloud RA does IdP-driven validation while the CA key lives in an HSM-backed CA you (or SecureW2) operate — clean separation by design.

### 7. Naming, uniqueness & validity strategy

- **Uniqueness** — serial numbers MUST be unique per CA and carry ≥64 bits of entropy (CA/B Forum) to defeat hash-collision prefix attacks. Subject/SAN namespace must be collision-free and authoritative.
- **Naming** — one canonical identity anchor per use case (UPN for users/Wi-Fi, FQDN for servers). Avoid stuffing humans-only metadata into security-relevant fields.
- **Validity strategy** — match lifetime to use and renewability. Short for public TLS (forced by the ecosystem), longer for auto-renewed device certs, long-but-rare for roots/intermediates. **Never issue a cert longer than your ability to revoke or rotate it.** Validity is covered in depth on Day 09.

---

## PRACTICE

We'll build a single openssl CA config with **multiple extension profiles**, then issue a `serverAuth` cert and a `clientAuth` user cert (with UPN SAN) from the *same* CA and diff them.

```bash
# ── 0. Workspace ───────────────────────────────────────────────────────
mkdir -p ca-lab && cd ca-lab
mkdir -p newcerts && touch index.txt && echo 1000 > serial

# ── 1. Root CA key + self-signed cert ──────────────────────────────────
openssl ecparam -name prime256v1 -genkey -noout -out ca.key.pem      # EC P-256 CA key
openssl req -x509 -new -key ca.key.pem -sha256 -days 3650 \
  -subj "/C=US/O=SecureW2 Lab/CN=SecureW2 Lab Issuing CA" \
  -out ca.cert.pem
```

Create `ca.cnf` — note the **separate extension sections = our profiles**:

```bash
cat > ca.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir            = .
database       = $dir/index.txt
serial         = $dir/serial
new_certs_dir  = $dir/newcerts
certificate    = $dir/ca.cert.pem
private_key    = $dir/ca.key.pem
default_md     = sha256
policy         = policy_loose
copy_extensions = none          # CRITICAL: do NOT copy attacker CSR extensions

[ policy_loose ]
commonName = supplied
organizationName = optional
countryName = optional

# ── PROFILE A: TLS server (serverAuth) ──────────────────────────────────
[ profile_server ]
basicConstraints = critical, CA:FALSE
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName   = @san_server
certificatePolicies = 1.3.6.1.4.1.99999.1.1     # private policy OID: "TLS server"

[ san_server ]
DNS.1 = vpn.corp.example
DNS.2 = www.corp.example

# ── PROFILE B: EAP-TLS / user cert with UPN SAN (clientAuth) ────────────
[ profile_user ]
basicConstraints = critical, CA:FALSE
keyUsage         = critical, digitalSignature
extendedKeyUsage = clientAuth, msSmartcardLogin   # 1.3.6.1.4.1.311.20.2.2
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName   = @san_user
certificatePolicies = 1.3.6.1.4.1.99999.1.2     # private policy OID: "IdP-vetted user"

[ san_user ]
email.1   = vamsi.h@securew2.com
# UPN as otherName; OID 1.3.6.1.4.1.311.20.2.2 = Microsoft UPN
otherName = msUPN;UTF8:vamsi.h@securew2.com
EOF
```

```bash
# ── 2. Issue the TLS SERVER cert (profile_server) ───────────────────────
openssl ecparam -name prime256v1 -genkey -noout -out server.key.pem
openssl req -new -key server.key.pem \
  -subj "/C=US/O=SecureW2 Lab/CN=vpn.corp.example" -out server.csr.pem
openssl ca -batch -config ca.cnf -extensions profile_server \
  -days 90 -in server.csr.pem -out server.cert.pem      # short-lived TLS

# ── 3. Issue the USER/UPN cert (profile_user) ───────────────────────────
openssl ecparam -name prime256v1 -genkey -noout -out user.key.pem
openssl req -new -key user.key.pem \
  -subj "/C=US/O=SecureW2 Lab/CN=Vamsi H" -out user.csr.pem
openssl ca -batch -config ca.cnf -extensions profile_user \
  -days 730 -in user.csr.pem -out user.cert.pem         # long-lived, auto-renewed device/user

# ── 4. Inspect each ─────────────────────────────────────────────────────
openssl x509 -in server.cert.pem -noout -text | grep -A1 -E "Key Usage|Extended|Alternative|Policies|Validity|Not After"
openssl x509 -in user.cert.pem   -noout -text | grep -A1 -E "Key Usage|Extended|Alternative|Policies|Validity|Not After"

# ── 5. DIFF the two profiles (the whole point) ──────────────────────────
diff <(openssl x509 -in server.cert.pem -noout -text) \
     <(openssl x509 -in user.cert.pem   -noout -text)
# Expect divergence on: EKU (serverAuth vs clientAuth+smartcard),
# KeyUsage (keyEncipherment present only on server), SAN (DNS vs UPN/email),
# certificatePolicies OID, and validity length.

# ── 6. Prove copy_extensions=none protects us ───────────────────────────
# Craft a malicious CSR asking for CA:TRUE + serverAuth, then issue as user:
openssl req -new -key user.key.pem -subj "/CN=evil" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "extendedKeyUsage=serverAuth" -out evil.csr.pem
openssl ca -batch -config ca.cnf -extensions profile_user -days 1 \
  -in evil.csr.pem -out evil.cert.pem
openssl x509 -in evil.cert.pem -noout -text | grep -A1 -E "Basic Constraints|Extended"
# Result: CA:FALSE and clientAuth — the malicious CSR extensions were DROPPED.
```

**Exercises:**
1. Add a third profile `profile_codesign` with EKU `codeSigning` and its own policy OID; issue a cert and diff it against the other two.
2. Change `copy_extensions = none` to `copyall`, re-issue the `evil.csr.pem`, and confirm the dangerous `CA:TRUE` leaks through. Then set it back and explain to a teammate why this single line is a CA-compromise-class bug.
3. Verify EKU enforcement: run `openssl verify -purpose sslserver -CAfile ca.cert.pem user.cert.pem` and observe it reject the user cert for server use.
4. Add a custom OID extension (e.g. `1.3.6.1.4.1.99999.2.1 = ASN1:UTF8String:dept=engineering`) to `profile_user` to simulate IdP attribute mapping, and dump it with `openssl asn1parse`.
5. Write the one-paragraph CP statement that *justifies* the 730-day validity on `profile_user` (hint: auto-renewal + revocation capability).

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. A CSR contains `basicConstraints=CA:TRUE` and `extendedKeyUsage=serverAuth`. The issued leaf cert has neither. Where did they go, and what would it mean if they were present?**
The CA dropped them — the CSR is only a *request*. A correctly configured CA applies its template's extensions and never copies untrusted CSR extensions (`copy_extensions=none`). If `CA:TRUE` leaked through, the "leaf" could sign other certs — a full PKI compromise. If a rogue `serverAuth` leaked into a client cert, you'd have a confused-deputy credential. This exact mistake (copying CSR basicConstraints) has caused real CA incidents.

**Q2. Why is EKU a security boundary and not just descriptive metadata?**
Because relying parties enforce it. A RADIUS server validating EAP-TLS *requires* `clientAuth`; a browser *requires* `serverAuth` for the connected host. EKU constrains *what a credential can be used for*, so a minimal, purpose-specific EKU prevents a Wi-Fi client cert from being repurposed as a web server cert. Stuffing both EKUs into one cert collapses the boundary.

**Q3. For EAP-TLS, where exactly is the identity the RADIUS server matches on — CN or SAN?**
SAN. Specifically `otherName` with the Microsoft UPN OID `1.3.6.1.4.1.311.20.2.2`, or `rfc822Name`. CN is legacy and increasingly ignored (CA/B Forum killed CN-as-identity for TLS years ago). If you map identity into CN only, modern matching policies will fail. SAN UPN is the authoritative anchor.

**Q4. DV, OV, EV — which gives the strongest cryptographic protection?**
None of them — they're identical cryptographically. The difference is purely *how rigorously the RA validated the requester's identity* before issuance. DV proves domain control only (a phisher can get a valid DV cert for a lookalike domain). The crypto is the same; the assurance about *who operates it* differs. This is why phishing-resistant client auth relies on internal RA-vetted IdP identity, not public DV.

**Q5. Explain separation of duties between RA and CA and the blast-radius argument.**
The RA decides *who* gets *what* (identity + authorization, no key power); the CA *signs* (holds the HSM-protected key, enforces template floors/ceilings, owns serials and revocation). Splitting them means a compromised RA can mis-authorize but cannot forge certs, while the high-value CA key stays minimally exposed and air-gapped/HSM-backed. It localizes damage. In SecureW2's model the cloud RA does IdP validation while the CA key stays HSM-bound.

**Q6. You map a user's `displayName` into the SAN and bake current group membership into a custom OID with a 2-year validity. Two problems — name them.**
(1) `displayName` is mutable — a rename breaks RADIUS identity matching and renewal continuity; bind to UPN/immutableID/objectGUID instead. (2) The group OID is a *point-in-time snapshot*; over a 2-year life the user changes roles and the cert now over-authorizes. Either shorten validity + auto-renew so attributes refresh, pair the cert with a live IdP/group lookup at auth time, or revoke-and-reissue on role change.

**Q7. What's the difference between a CP and a CPS, and what is a policy OID for?**
The CP says *what* the PKI promises (validation rigor, key sizes, allowed uses, liability); the CPS says *how* the CA operationally delivers it (HSM handling, RA procedures, key ceremonies, audits). Both follow the RFC 3647 outline. The **policy OID** is the machine-enforceable handle: it's stamped into `certificatePolicies`, and a relying party can require a specific OID before trusting a cert — so a generic cert can't be reused in a high-assurance context.

**Q8. Why must serial numbers carry ≥64 bits of entropy?**
To defeat chosen-prefix hash-collision attacks against the cert's signature. If serials were predictable/sequential, an attacker who could partially influence cert contents had a path to crafting a colliding certificate. The CA/B Forum mandates ≥64 bits of CSPRNG entropy in the serial so the attacker can't predict that field — it's a cheap, effective collision defense.

**Q9. In a SecureW2 JoinNow deployment, walk the path from an Entra ID user to a client cert with the right UPN.**
The user authenticates to JoinNow via SAML/OIDC against Entra ID. JoinNow's RA reads the assertion claims, extracts `userPrincipalName` (and `mail`, groups, etc.), and applies the attribute-mapping policy: UPN → SAN `otherName(1.3.6.1.4.1.311.20.2.2)`, mail → SAN `rfc822Name`, and group/role → template selection + custom policy OID. The managed CA (HSM-backed) then mints a `clientAuth` cert with `CA:FALSE`, minimal KU, a short-or-auto-renewed validity, and the right policy OID. The device installs it (often TPM-bound) and uses it for EAP-TLS, where the RADIUS server matches on the UPN SAN.

---

➡ Next: [Day 09 — The Certificate Lifecycle: Renewal, Rotation & Expiry](day-09-certificate-lifecycle-renewal-rotation.md)
