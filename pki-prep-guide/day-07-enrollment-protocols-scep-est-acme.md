# Day 07 — Certificate Enrollment Protocols

## THEORY

### 1. The Enrollment Problem

Yesterday you learned how a single device generates a key and builds a CSR. Now scale that to **50,000 laptops, phones, and IoT sensors** — none of which you'll touch by hand. The enrollment problem is:

> How do you get a *trusted* certificate, with the *right* attributes, onto thousands of devices **automatically**, while proving each requester is **authorized**, **without ever exposing the private key**, and renew them **before they expire** — forever?

Every protocol in this chapter is an answer to that question, differing mainly in:

- **Authorization** — how the CA knows the requester is allowed a cert (shared secret? TLS client cert? domain control?).
- **Transport / security** — raw HTTP with envelope crypto vs modern TLS.
- **Automation** — manual, MDM-pushed, or fully unattended renewal.
- **Audience** — internal device PKI vs public web PKI.

A SecureW2-style platform fronts these protocols with a **gateway** that the device (or the MDM) talks to, bridging the device to the CA and enforcing policy/identity. Keep that picture in mind throughout.

### 2. Manual Enrollment (the baseline)

The device generates a key + CSR; a human submits the CSR to the CA (web portal, email, ticket), an admin approves it, the cert comes back, and someone installs it. Also called the **PKCS#10 in / PKCS#7 out** flow.

- **Pros**: simple, full human control, fine for a handful of servers or the offline issuance of intermediate CAs.
- **Cons**: does not scale, error-prone, and — fatally — **nobody manually renews 50,000 certs**. Expired certs are the #1 cause of outages and Wi-Fi auth failures. Manual enrollment is a last resort, not a strategy.

### 3. SCEP — Simple Certificate Enrollment Protocol

The old workhorse of device PKI (originally Cisco; now `draft`/RFC 8894). Despite "simple," it's everywhere because **every MDM speaks it**: Intune, Jamf, Workspace ONE, etc.

**How it works (simplified):**

1. Device gets the CA cert (GetCACert) so it can trust and encrypt to the CA.
2. Device generates its key pair + CSR.
3. Device wraps the CSR in a **PKCS#7** envelope, *encrypted to the CA's public key and signed by the device*, including a **challengePassword**.
4. CA validates the challenge, issues the cert, returns it (PKCS#7).
5. Device polls (`GetCertInitial`) if issuance is pending.

**The challengePassword (shared secret):** SCEP's authorization mechanism. The device proves it's allowed a cert by presenting a secret the CA expects.

**How MDMs use SCEP (the real-world flow):**

In Intune/Jamf, the **MDM is the trusted broker**. The flow:

1. MDM authenticates the device/user it already manages.
2. MDM pushes a **SCEP profile** to the device containing the SCEP URL, the cert template/parameters, **and a one-time, per-device challenge** that the MDM obtained from the SCEP server (e.g., SecureW2's gateway, or NDES via the Intune Certificate Connector).
3. The device's TPM/Secure Enclave generates the key, builds the CSR, and submits it with that challenge.
4. The gateway validates the challenge *and* (in better designs) re-checks with the MDM that the device is still compliant, then issues.

**SCEP weaknesses — know these cold:**

- **The shared-secret / static-challenge problem**: classic NDES uses a **static** enrollment password (or a short list). Anyone who learns it can enroll *any* identity. Worse, basic SCEP often **doesn't strongly bind the challenge to a specific subject** — a stolen challenge can request a cert for a different CN. This is the single biggest SCEP risk.
- **Weak/legacy crypto**: original SCEP leaned on RSA + SHA-1 and weak envelope ciphers; modern implementations patch this but the spec's age shows.
- **No native TLS**: SCEP secures the *message* (PKCS#7 envelope) rather than the *channel*, which is harder to reason about and audit.
- **No standardized renewal/authz story**: re-enrollment is implementation-specific.

**Dynamic SCEP challenges (the mitigation):** Instead of a static password, the MDM/gateway issues a **unique, single-use, short-lived challenge per enrollment request**, tied to the specific device/user and subject. Microsoft NDES + Intune does this via the Certificate Connector; SecureW2's SCEP gateway does it natively and additionally validates the request against the MDM/IdP before issuance. **Always use dynamic, per-device challenges — never a shared static SCEP password in production.**

### 4. EST — Enrollment over Secure Transport (RFC 7030)

EST is the **modern, TLS-based replacement for SCEP**. It throws out PKCS#7 message-level crypto and runs everything over **HTTPS/TLS**, which solves SCEP's biggest design smells.

**Key endpoints (all under `/.well-known/est/`):**

| Endpoint | Purpose |
|----------|---------|
| `/cacerts` | Get the CA cert chain (over TLS) |
| `/simpleenroll` | Submit a PKCS#10 CSR, get a PKCS#7 cert back |
| `/simplereenroll` | **Renewal** — re-enroll using the existing cert as auth |
| `/serverkeygen` | (Optional) server generates the key — use sparingly |
| `/csrattrs` | CA tells the client which CSR attributes it expects |

**Why EST is better:**

- **TLS does the heavy lifting**: confidentiality, integrity, and **mutual authentication** come from TLS itself. The device authenticates with a TLS client cert (or HTTP Basic/bootstrap credential for the first enrollment).
- **Clean re-enrollment**: `/simplereenroll` lets a device renew by authenticating with its *current* (valid) certificate — no shared password, the existing cert *is* the credential. This is exactly the unattended-renewal story SCEP lacks.
- **`/csrattrs`** lets the CA tell the client what to put in the CSR, reducing template mismatch.
- **Modern crypto & smaller footprint**, well-suited to IoT (it's an IETF standard born for constrained devices).

**Bootstrap problem:** the *first* enrollment needs *some* credential (a one-time password, a bootstrap/birth cert from the manufacturer, or a manually trusted TLS connection). After that, the issued cert bootstraps all future renewals via `/simplereenroll`.

### 5. ACME — Automated Certificate Management Environment (RFC 8555)

ACME is what made **Let's Encrypt** possible and now dominates web PKI. Its killer feature: **the CA verifies you control the identity (domain), then everything is fully automated — issuance *and* renewal — with no human and no pre-shared secret.**

**The flow:**

1. Client creates an **account key** with the ACME server.
2. Client requests a cert for `example.com` → server replies with **challenges**.
3. Client proves control via one challenge type, server validates, then client submits CSR and downloads the cert.
4. Renewal = re-run the whole thing on a timer (certs are deliberately short-lived, e.g. 90 days).

**Challenge types:**

| Challenge | Proves control by... | Use when |
|-----------|---------------------|----------|
| **http-01** | Serving a token at `http://domain/.well-known/acme-challenge/<token>` | You control a web server on port 80 |
| **dns-01** | Publishing a TXT record `_acme-challenge.domain` | You control DNS; **only way to get wildcards** `*.domain` |
| **tls-alpn-01** | Presenting a special cert during a TLS handshake on port 443 (ALPN) | Port 80 blocked; want validation purely over TLS |

**ACME for internal PKI & device certs:** ACME isn't only for public certs. Internal/private CAs (smallstep CA, EJBCA, HashiCorp Vault, MS AD CS via add-ons, and SecureW2 platforms) increasingly expose **ACME endpoints** so servers and even devices auto-renew internal certs. For devices, ACME variants exist (e.g. **device-attestation challenges**, draft work on ACME with TPM/Secure-Enclave attestation) that prove device identity instead of domain control — bringing ACME's hands-off renewal to the device-PKI world. The win is the same: **short-lived certs + fully automated renewal = no expiry outages.**

### 6. CMP — Certificate Management Protocol (briefly)

**CMP (RFC 4210, modernized by "Lightweight CMP" RFC 9483)** is the heavyweight, full-lifecycle protocol: enrollment, renewal, revocation, key update, and CA-to-CA messaging all in one. It's powerful and rigorous but complex. It dominates in **telco / 3GPP (5G base stations), industrial, and high-assurance European deployments**. Think "EST's bigger, more capable, more complicated cousin." You rarely meet CMP in MDM/Wi-Fi land, but name-drop it correctly: it's the protocol of choice where strict, standardized full lifecycle management is mandated.

### 7. Protocol Comparison

| Feature | Manual | **SCEP** | **EST** | **ACME** | CMP |
|---------|--------|----------|---------|----------|-----|
| RFC / origin | — | RFC 8894 (Cisco) | RFC 7030 | RFC 8555 | RFC 4210 / 9483 |
| Transport security | n/a | PKCS#7 message envelope | **TLS (HTTPS)** | **TLS (HTTPS)** | message-level + transports |
| Initial authorization | human | **challengePassword** (shared/dynamic) | TLS client cert / Basic / OTP | **domain/identity control** challenge | shared secret / cert / RA |
| Renewal story | manual | weak/ad-hoc | **`/simplereenroll`** (cert-based) | **fully automated, on timer** | full key-update support |
| Automation level | none | MDM-driven | high | **fully unattended** | high (complex) |
| Sweet spot | servers, CA offline | **MDM device certs** (Intune/Jamf) | modern device/IoT PKI | **web servers, internal auto-renew** | telco/5G, high assurance |
| Biggest weakness | doesn't scale | shared-secret problem | bootstrap credential | mostly domain-control oriented | complexity |

**Practitioner takeaway:** For **MDM-managed user/device certs today, SCEP (with dynamic challenges)** is still the dominant real-world choice simply because every MDM supports it — and a SecureW2 gateway hardens it by validating each request against the MDM/IdP. **EST** is where you go for modern, TLS-native device enrollment. **ACME** is the default for anything web-facing and for unattended internal-cert renewal. **CMP** for telco/regulated full-lifecycle needs.

---

## PRACTICE

```bash
# ─────────────────────────────────────────────────────────────
# 1. SCEP — simulate enrollment with sscep (client) against a SCEP server
#    (e.g. SecureW2 gateway, MS NDES, or EJBCA SCEP alias)
# ─────────────────────────────────────────────────────────────

# Step 1: fetch the CA cert(s) so we can trust/encrypt to the CA
sscep getca -u http://scep.acme.example/cgi-bin/pkiclient.exe -c ca.crt

# Step 2: generate the device key + a CSR carrying the challengePassword
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out device.key
openssl req -new -key device.key -out device.csr \
  -subj "/CN=laptop-7f3a.acme.example" \
  -passin pass: -passout pass:                # challenge supplied below

# Step 3: enroll — the per-device challenge is the SCEP authorization
sscep enroll \
  -u http://scep.acme.example/cgi-bin/pkiclient.exe \
  -c ca.crt -k device.key -r device.csr \
  -l device.crt \
  -E des -S sha256 \
  -t 5 -n 3            # poll: wait 5s, up to 3 times if issuance is pending
# In an MDM (Intune/Jamf) this entire exchange is driven by a pushed SCEP profile,
# and the challenge above is a DYNAMIC, single-use, per-device password — never static.

# ─────────────────────────────────────────────────────────────
# 2. EST — enroll over TLS with curl (RFC 7030 endpoints)
# ─────────────────────────────────────────────────────────────

# 2a. Get the CA chain over TLS (base64 PKCS#7)
curl -s https://est.acme.example/.well-known/est/cacerts \
  -o cacerts.p7 --cacert bootstrap-ca.crt
openssl base64 -d -in cacerts.p7 | openssl pkcs7 -inform DER -print_certs

# 2b. Build a CSR (DER, base64) and simpleenroll, authenticating with TLS + Basic
openssl req -new -key device.key -subj "/CN=laptop-7f3a.acme.example" \
  -outform DER | openssl base64 > device.b64

curl -s https://est.acme.example/.well-known/est/simpleenroll \
  --cacert bootstrap-ca.crt \
  -u "bootstrap-user:bootstrap-otp" \
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data @device.b64 \
  -o newcert.p7
openssl base64 -d -in newcert.p7 | openssl pkcs7 -inform DER -print_certs -out device.crt

# 2c. RENEWAL — re-enroll authenticating with the CURRENT cert (no password!)
curl -s https://est.acme.example/.well-known/est/simplereenroll \
  --cacert cacerts.crt \
  --cert device.crt --key device.key \      # the existing cert IS the credential
  -H "Content-Type: application/pkcs10" \
  -H "Content-Transfer-Encoding: base64" \
  --data @device.b64 -o renewed.p7

# ─────────────────────────────────────────────────────────────
# 3. ACME — certbot against the Let's Encrypt STAGING environment
#    (staging = no rate limits, untrusted certs: safe for practice)
# ─────────────────────────────────────────────────────────────

# 3a. Dry-run / staging issuance with the http-01 challenge (standalone server)
certbot certonly --staging --standalone \
  -d www.acme.example \
  --agree-tos -m vamsi.h@securew2.com --non-interactive
# certbot: places token at /.well-known/acme-challenge/<token>, LE fetches it over :80

# 3b. dns-01 challenge — REQUIRED for a wildcard *.acme.example
certbot certonly --staging --manual --preferred-challenges dns \
  -d '*.acme.example' -d acme.example \
  --agree-tos -m vamsi.h@securew2.com
# certbot prints a TXT value to publish at _acme-challenge.acme.example, then validates

# 3c. Test automated renewal without actually hitting prod limits
certbot renew --dry-run
# Conceptually: this is the whole point — a timer/systemd unit runs this; certs
# (≈90 days) renew unattended at ~60 days. No human, no expiry outage.

# ─────────────────────────────────────────────────────────────
# 4. ACME against an INTERNAL CA (smallstep) for device/server certs
# ─────────────────────────────────────────────────────────────
step ca certificate "host.internal.acme" host.crt host.key \
  --provisioner acme --acme https://ca.internal.acme/acme/acme/directory
```

**Exercises:**

1. Diagram the Intune SCEP flow end to end: where the key is generated, where the dynamic challenge comes from, what the SCEP gateway validates, and what travels over the wire. Mark the one point where a *static* challenge would break security.
2. Using EST, perform an initial `/simpleenroll` with a bootstrap OTP, then a `/simplereenroll` using the issued cert. Explain why the second call needs no password.
3. Get a *wildcard* staging cert with certbot. Explain why http-01 cannot issue a wildcard and dns-01 can.
4. Build the protocol comparison table from memory (SCEP/EST/ACME) across: transport, initial auth, renewal, sweet spot. Then justify why an MDM rollout today still usually picks SCEP.
5. Research and write 5 sentences on Lightweight CMP (RFC 9483) and name one industry where it's mandated.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. SCEP is called "insecure" yet every MDM uses it. Reconcile that.**
SCEP's *protocol-level* weakness is the **shared-secret challengePassword** — a static one can be stolen and used to enroll arbitrary identities, and basic SCEP weakly binds the challenge to a subject. It's still ubiquitous because every MDM speaks it. The reconciliation is the **deployment**: you make the challenge **dynamic, single-use, per-device**, and you front SCEP with a gateway (e.g., SecureW2/NDES+Intune Connector) that validates each request against the MDM/IdP *before* issuing. Hardened that way, SCEP's practical risk drops sharply even though the spec is dated.

**Q2. What concretely does EST fix versus SCEP?**
EST moves security from a **PKCS#7 message envelope** to the **TLS channel**, giving channel-level confidentiality, integrity, and mutual auth for free, and modern crypto. Critically it adds a clean **renewal path (`/simplereenroll`)** where the device authenticates with its *current cert* — no shared password — solving SCEP's biggest operational gap. It also adds `/csrattrs` so the CA can tell the client what to request, reducing template mismatches.

**Q3. A device's cert is valid and about to expire. Walk through how it renews under EST vs SCEP vs ACME.**
- **EST**: device calls `/simplereenroll` over mutual TLS, presenting the *current valid cert* as its credential; CA issues a fresh one. Clean and standardized.
- **SCEP**: no standard renewal — implementations re-run enrollment, which means needing a fresh challenge from the MDM; this is the ad-hoc, weaker part of SCEP.
- **ACME**: a timer simply re-runs the full issuance (re-proving domain/identity control) well before expiry; fully unattended. The ACME model assumes short-lived certs and continuous renewal.

**Q4. Why can dns-01 issue a wildcard certificate but http-01 cannot?**
A wildcard `*.example.com` asserts control over the *entire domain namespace*, which can't be proven by serving a file on one host (http-01 only proves control of that specific name/host). **dns-01** proves authority over the **DNS zone** itself by publishing a TXT record at `_acme-challenge.example.com`, and zone control is exactly the authority a wildcard represents — so Let's Encrypt requires dns-01 for wildcards.

**Q5. ACME requires "no pre-shared secret," but SCEP/EST need a challenge or bootstrap credential. How does ACME avoid that, and what's the catch?**
ACME replaces a pre-shared secret with a **proof of control over the identity** (domain via http/dns/tls-alpn challenge). You don't need a secret because you demonstrate you *are* the entity by manipulating something only the owner can (web root, DNS zone, TLS handshake). The catch: it's naturally **identity/domain-oriented**, so applying it to bare *device* identity needs extensions like **device-attestation challenges** (proving a TPM/Secure Enclave) rather than domain control.

**Q6. In an MDM-driven SCEP enrollment, the private key — does it ever reach the MDM or the SCEP server? Where exactly is it generated?**
No. The key is generated **on the device, in its TPM/Secure Enclave, non-exportable**, triggered by the pushed SCEP profile. Only the **CSR (public key + challenge)** travels through the MDM to the SCEP gateway. The MDM brokers *authorization and the dynamic challenge*; it never sees the private key. That's what preserves per-device non-repudiation even though the MDM orchestrates the flow.

**Q7. Someone proposes EST's `/serverkeygen` so the CA generates keys for IoT devices that "can't generate good entropy." Evaluate.**
It's a legitimate EST feature and sometimes the pragmatic answer for tiny devices with poor RNGs — but it **reintroduces the central-generation / key-transport problem**: the private key now exists on the server and must be shipped to the device, weakening non-repudiation and adding an exfiltration surface. Prefer fixing entropy (hardware RNG, TPM) and keeping on-device generation. Use `/serverkeygen` only when the device genuinely cannot generate a key and the threat model accepts it, over a strongly authenticated TLS channel.

**Q8. When would you reach for CMP instead of ACME or EST?**
When you need **standardized, rigorous full-lifecycle management** — enrollment, renewal, key update, revocation, and CA-to-CA messaging — under regulatory or vendor mandate. The classic case is **telco / 3GPP 5G** base-station provisioning, and high-assurance industrial/European deployments, where Lightweight CMP (RFC 9483) is specified. You accept its complexity in exchange for completeness and standardization that ACME/EST don't fully cover.

**Q9. A customer's Wi-Fi keeps failing every 90 days for a chunk of devices. What enrollment-design root cause do you suspect, and how do EST/ACME prevent it?**
That cadence screams **certs expiring without automated renewal** — likely a manual or static-challenge SCEP setup where renewal never fires. The fix is a protocol with **unattended renewal**: **EST `/simplereenroll`** (renew using the current cert) or **ACME** (timer-based re-issue well before expiry), so devices roll over to fresh certs automatically and the RADIUS/EAP-TLS auth never sees an expired cert. Short-lived certs are only safe when renewal is automatic — that's the whole design philosophy.

➡ Next: [Day 08 — Certificate Issuance: Templates & Policies](day-08-certificate-issuance-templates-policies.md)
