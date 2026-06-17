# Day 10 — Revocation: CRL, OCSP & Short-Lived Certs

## THEORY

### 1. Why revocation exists at all

A certificate is a *time-bounded* trust assertion: "this CA vouches that this
public key belongs to this subject until `notAfter`." But the real world is
messier than the validity window. Sometimes the CA needs to retract that
assertion **before** it naturally expires. That retraction is **revocation**.

The three classic triggers, all of which you will hit in a real PKI/RADIUS shop:

- **Key compromise** — the private key leaked (stolen laptop, exfiltrated HSM
  backup, Heartbleed-style memory disclosure). This is the *only* reason that
  truly demands cryptographic invalidation, because the attacker can now
  impersonate the subject.
- **Employee / device offboarding** — someone leaves, or a managed device is
  decommissioned or stolen. The cert is still cryptographically valid, but the
  *entitlement* behind it is gone. In a SecureW2 deployment this maps to a user
  being disabled in the IdP, which should kill their device certs for network
  access.
- **Mis-issuance** — the CA issued a cert it shouldn't have: wrong SAN, wrong
  subject, domain-validation bypass, a cert with the wrong policy OID, or a
  cert issued to the wrong requester. CAs are *required* by the CA/Browser
  Forum Baseline Requirements to revoke mis-issued certs within strict
  timelines (24 hours for key compromise / fraudulent issuance, 5 days for
  lesser problems).

> **Gotcha:** Revocation does not "delete" anything. The cert still exists and
> is still cryptographically well-formed. Revocation only works if the
> *relying party* (browser, RADIUS server, VPN gateway) actually **checks**
> revocation status. If nobody checks, revocation is theater.

### 2. Revocation reasons (RFC 5280 CRLReason)

When you revoke, you stamp a reason code. These are not cosmetic — some carry
real semantics for relying parties and for re-validation.

| Code | Reason | Meaning / practitioner note |
|------|--------|------------------------------|
| 0 | `unspecified` | No reason given. Avoid; gives RPs nothing. |
| 1 | `keyCompromise` | Private key is known/suspected stolen. **Hard fail** territory. |
| 2 | `cACompromise` | A CA key is compromised — nukes everything under it. Catastrophic. |
| 3 | `affiliationChanged` | Subject's name/affiliation changed (e.g., employee changed roles). |
| 4 | `superseded` | Reissued/rekeyed; the new cert replaces this one. |
| 5 | `cessationOfOperation` | Entity no longer operates (service retired, device decommissioned). |
| 6 | `certificateHold` | Temporary suspension — the *only* reversible state. |
| 8 | `removeFromCRL` | Used with delta CRLs to lift a `certificateHold`. |
| 9 | `privilegeWithdrawn` | Entitlement withdrawn (classic offboarding reason). |
| 10 | `aACompromise` | Attribute Authority compromise. |

> **Gotcha:** `certificateHold` (suspension) is widely **distrusted** in the
> public web PKI — the CA/Browser Forum prohibits suspension of TLS server
> certs precisely because a "held then un-held" cert breaks the assumption that
> revocation is permanent. In private/enterprise PKI it's still occasionally
> used for temporary lockouts, but plan for it being ambiguous.

### 3. CRLs — Certificate Revocation Lists

A **CRL** is a signed, timestamped list of revoked serial numbers, published by
the CA (or a designated CRL issuer). Structure:

```
CertificateList ::= {
  tbsCertList:
    version, signatureAlg, issuer,
    thisUpdate,            -- when this CRL was produced
    nextUpdate,            -- when the next CRL is promised (freshness window)
    revokedCertificates [ { serialNumber, revocationDate, crlEntryExtensions } ... ],
    crlExtensions  ( CRL Number, Authority Key ID, IDP, etc. )
  signatureAlgorithm,
  signatureValue            -- CA signs the whole TBS list
}
```

How a relying party finds the CRL: the leaf cert carries a **CRL Distribution
Point (CDP)** extension — an HTTP(S) (occasionally LDAP) URL pointing at the
CRL. The RP downloads it, checks the CA signature, checks `nextUpdate` for
freshness, and searches for the cert's serial.

**Full vs Delta CRLs:**

- **Full ("base") CRL** — the complete list of all currently-revoked,
  not-yet-expired serials. Simple, but it only grows.
- **Delta CRL** — a small CRL listing *only* changes since a referenced base
  CRL (via the `Delta CRL Indicator` and `Base CRL Number`). RPs combine
  base + delta to get current state. Lets you publish small, frequent updates
  without re-shipping a giant base list every time.

### 4. CRL scaling problems (why CRLs hurt)

This is the heart of the topic — and a favorite interview area.

- **Size** — a busy CA with millions of certs and a meaningful revocation rate
  produces multi-megabyte CRLs. Every RP downloads the *whole thing* to check
  *one* cert. This is brutal on mobile, IoT, and high-fan-out RADIUS servers.
  (Partitioning via multiple CDPs / IDP-scoped CRLs is the mitigation.)
- **Freshness lag / the `nextUpdate` window** — a CRL is valid until
  `nextUpdate`. If you revoke a key *right after* a CRL is published, RPs may
  cache the stale CRL for hours or days and keep trusting the compromised cert
  until the next CRL drops. You can't revoke faster than your CRL cadence.
- **Caching trade-off** — short `nextUpdate` = fresher but more download load;
  long `nextUpdate` = cheaper but a wider compromise window. There is no free
  lunch.
- **Hard-fail unfriendly** — because CRLs are big and CDPs go down, most clients
  end up soft-failing (see §6), which guts the security value.

### 5. OCSP — Online Certificate Status Protocol

OCSP (RFC 6960) flips the model: instead of downloading the whole list, the RP
asks an **OCSP responder** about *one specific cert*.

- **Request:** `{ issuerNameHash, issuerKeyHash, serialNumber }` (a "CertID"),
  sent over HTTP (GET with base64 for small requests, or POST).
- **Response:** a **signed** answer of `good`, `revoked`, or `unknown`, plus
  `thisUpdate` / `nextUpdate` and optionally a `revocationReason`.
  - `good` ≠ "this cert was ever issued" — it means "not on the revoked list."
    A responder using a precomputed CRL can answer `good` for a serial it has
    no record of. (RFC 6960 lets you require the responder to assert issuance.)
- **Where the URL comes from:** the **Authority Information Access (AIA)**
  extension in the leaf, `accessMethod = id-ad-ocsp`, gives the OCSP responder
  URL. (AIA also carries `id-ad-caIssuers` — that's for fetching the issuer
  cert, a different thing; don't confuse the two.)

**Why OCSP isn't a silver bullet:**

- **Privacy leak** — the responder (often run by the CA) learns *which sites
  the user visits and when*, because every TLS connection triggers a status
  query for that site's cert. This is a real reason browsers backed away from
  client-driven OCSP.
- **Latency & availability** — an extra round-trip to a third-party responder
  on the critical path of every handshake; if the responder is slow or down,
  the handshake stalls.

### 6. The OCSP soft-fail problem (this is the security hole)

When a browser/client can't reach the OCSP responder (timeout, DNS failure,
captive portal), it has two choices:

- **Hard-fail:** refuse the connection. Secure, but one responder outage takes
  down access to *every* site — operationally unacceptable, so almost nobody
  does this by default.
- **Soft-fail:** assume the cert is fine and proceed. This is what virtually all
  browsers do.

The fatal consequence: **an attacker who can already do a man-in-the-middle
(the exact scenario where you'd want revocation to save you) can simply block
the OCSP query.** The client soft-fails and accepts the stolen/revoked cert.
Soft-fail revocation checking is therefore "secure only against attackers who
aren't attacking you." This is why Chrome largely **disabled** live OCSP/CRL
checking for leaf certs and shifted to a pushed, curated revocation set
(CRLSets / CRLite-style aggregation).

### 7. OCSP stapling & must-staple

**OCSP stapling** (TLS extension *Certificate Status Request*, RFC 6066) fixes
several problems at once:

- The **server** periodically fetches a fresh, signed OCSP response for *its
  own* cert and **staples** it into the TLS handshake (`CertificateStatus`
  message).
- The client gets the revocation proof for free, in-band, with **no extra
  round-trip** and **no privacy leak** to the CA.
- The staple is short-lived and CA-signed, so the server can't forge a `good`.

But stapling alone is still soft-fail: an MITM can just *strip* the staple and
the client proceeds. The fix is **OCSP Must-Staple** — the
`TLS Feature` extension (`status_request`, RFC 7633) baked into the cert. It
tells clients: "a valid staple is **mandatory**; if it's missing, hard-fail."
Now stripping the staple breaks the connection. Adoption is low because a
single stapling misconfiguration causes a hard outage — a real operational
risk that many operators won't accept.

### 8. The revocation-checking gap in practice

Putting it together: in the public web PKI, *reliable, timely, hard-fail
revocation basically does not exist.* CRLs are too big, OCSP soft-fails,
stapling is optional and strippable, must-staple is rare. The industry's honest
answer has become: **stop relying on revocation; shrink the validity window
instead.**

### 9. Short-lived certificates — the modern alternative

If a cert only lives **hours to days**, the compromise window is bounded by its
lifetime, so you may not *need* revocation at all — the cert expires before a
slow revocation channel would have caught up anyway. This is why:

- TLS cert max validity has been ratcheting down (398 days → and the CA/B Forum
  has agreed to push public TLS lifetimes toward ~47 days by 2029).
- Internal/automated PKI (SPIFFE/SVID, service meshes, cloud workload identity)
  routinely issues certs valid for **minutes to hours**, auto-renewed via ACME
  or an internal CA API. Revocation is replaced by "just let it expire."

The trade-off: short-lived certs **demand automation**. A human cannot renew a
1-hour cert. This is exactly the bridge into Day 11 (CLM).

### 10. Revocation in EAP-TLS / network auth (the SecureW2 angle)

In **EAP-TLS**, the client presents a *client* certificate and the **RADIUS
server is the relying party.** So the RADIUS server is the thing that must
decide whether a client cert is still trustworthy:

- It can be configured to **check a CRL** (FreeRADIUS: `check_crl = yes`,
  pointing the EAP `tls` block at a CA dir with CRLs, or fetching CDP). It can
  also do OCSP (`ocsp { enable = yes ... }` in FreeRADIUS).
- **But network auth has a far better lever than PKI revocation:** the network
  layer itself. Because the user re-authenticates against the RADIUS/IdP on
  every (re)association and you control RADIUS, you can:
  - **Disable the user/device in the IdP** → next auth fails instantly, no CRL
    propagation delay.
  - Issue a **Change of Authorization (CoA) / Disconnect-Message** (RFC 5176)
    to the NAS/controller and **kick the device off the network right now**,
    then deny re-auth.
  - Use **short-lived device certs** so a deprovisioned device's cert simply
    stops being renewed.

This is why managed-PKI vendors like SecureW2 lean on **policy-driven,
instant deauth via the network + automated short-lived/auto-renewed device
certs** rather than fragile CRL/OCSP propagation. PKI revocation still exists as
a backstop, but the *operational* kill switch is the RADIUS policy and CoA.

> **Interview-grade summary:** "On the web, revocation is best-effort and we
> compensate with short lifetimes. On the network, we don't wait for CRL/OCSP —
> we revoke entitlement at the IdP and CoA the session off in real time."

---

## PRACTICE

```bash
# ─────────────────────────────────────────────────────────────
# 0. Workspace + a minimal CA that supports CRLs
# ─────────────────────────────────────────────────────────────
mkdir -p ~/revlab && cd ~/revlab
mkdir -p demoCA/{newcerts,crl,private}
touch demoCA/index.txt                 # the CA database (issued/revoked state)
echo 1000 > demoCA/serial              # next serial number
echo 1000 > demoCA/crlnumber           # CRL sequence counter

# Minimal openssl.cnf for CA + CRL operations
cat > openssl.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./demoCA
database          = $dir/index.txt
new_certs_dir     = $dir/newcerts
certificate       = $dir/ca.crt.pem
private_key       = $dir/private/ca.key.pem
serial            = $dir/serial
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl.pem
default_md        = sha256
default_crl_days  = 7                   # nextUpdate = thisUpdate + 7 days
policy            = policy_any
x509_extensions   = leaf_exts
default_days      = 365

[ policy_any ]
commonName        = supplied
countryName       = optional
organizationName  = optional

[ req ]
distinguished_name = dn
[ dn ]

[ leaf_exts ]
# CDP + AIA(OCSP) so relying parties know where to check
crlDistributionPoints = URI:http://localhost:8888/ca.crl.pem
authorityInfoAccess   = OCSP;URI:http://localhost:8081
basicConstraints      = CA:FALSE
keyUsage              = digitalSignature, keyEncipherment

[ ocsp_signer ]
basicConstraints  = CA:FALSE
keyUsage          = critical, digitalSignature
extendedKeyUsage  = critical, OCSPSigning   # id-kp-OCSPSigning is mandatory
EOF

# ─────────────────────────────────────────────────────────────
# 1. Create the root CA
# ─────────────────────────────────────────────────────────────
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout demoCA/private/ca.key.pem -out demoCA/ca.crt.pem \
  -days 3650 -subj "/CN=RevLab Root CA"

# ─────────────────────────────────────────────────────────────
# 2. Issue a leaf cert (the one we'll later revoke)
# ─────────────────────────────────────────────────────────────
openssl req -newkey rsa:2048 -nodes \
  -keyout leaf.key.pem -out leaf.csr.pem -subj "/CN=client.revlab.local"
openssl ca -config openssl.cnf -batch -in leaf.csr.pem -out leaf.crt.pem
openssl x509 -in leaf.crt.pem -noout -serial -subject

# Inspect the CDP + AIA we embedded
openssl x509 -in leaf.crt.pem -noout -text | grep -A2 "CRL Distribution\|Authority Information"

# ─────────────────────────────────────────────────────────────
# 3. Generate an (empty) CRL, then verify the leaf is GOOD
# ─────────────────────────────────────────────────────────────
openssl ca -config openssl.cnf -gencrl -out demoCA/crl/ca.crl.pem
openssl crl -in demoCA/crl/ca.crl.pem -noout -text | head -20   # see thisUpdate/nextUpdate/CRL Number

# Verify with revocation checking ON (should PASS — not yet revoked)
cat demoCA/ca.crt.pem demoCA/crl/ca.crl.pem > bundle.pem
openssl verify -crl_check -CAfile bundle.pem leaf.crt.pem
# => leaf.crt.pem: OK

# ─────────────────────────────────────────────────────────────
# 4. Revoke the cert, regenerate the CRL, verify it now FAILS
# ─────────────────────────────────────────────────────────────
openssl ca -config openssl.cnf -revoke leaf.crt.pem \
  -crl_reason keyCompromise           # stamp a reason code
openssl ca -config openssl.cnf -gencrl -out demoCA/crl/ca.crl.pem

cat demoCA/ca.crt.pem demoCA/crl/ca.crl.pem > bundle.pem
openssl verify -crl_check -CAfile bundle.pem leaf.crt.pem
# => error 23 at 0 depth lookup: certificate revoked   (this is the win)

# ─────────────────────────────────────────────────────────────
# 5. Stand up a local OCSP responder and query it
# ─────────────────────────────────────────────────────────────
# Issue a dedicated OCSP-signing cert (EKU = OCSPSigning)
openssl req -newkey rsa:2048 -nodes -keyout ocsp.key.pem -out ocsp.csr.pem \
  -subj "/CN=RevLab OCSP Responder"
openssl ca -config openssl.cnf -batch -extensions ocsp_signer \
  -in ocsp.csr.pem -out ocsp.crt.pem

# Run the responder (foreground; use a second terminal for the query)
openssl ocsp -index demoCA/index.txt -port 8081 \
  -CA demoCA/ca.crt.pem \
  -rkey ocsp.key.pem -rsigner ocsp.crt.pem -text &

# Query the responder for our (now revoked) leaf
openssl ocsp -CAfile demoCA/ca.crt.pem -issuer demoCA/ca.crt.pem \
  -cert leaf.crt.pem -url http://localhost:8081 -resp_text
# => Cert Status: revoked   Reason: keyCompromise

# ─────────────────────────────────────────────────────────────
# 6. Compare against a still-good cert
# ─────────────────────────────────────────────────────────────
openssl req -newkey rsa:2048 -nodes -keyout good.key.pem -out good.csr.pem \
  -subj "/CN=good.revlab.local"
openssl ca -config openssl.cnf -batch -in good.csr.pem -out good.crt.pem
openssl ocsp -CAfile demoCA/ca.crt.pem -issuer demoCA/ca.crt.pem \
  -cert good.crt.pem -url http://localhost:8081
# => good.crt.pem: good
```

**Exercises:**

1. Set `default_crl_days = 1`, revoke a cert, then *do not* regenerate the CRL.
   Show that `openssl verify -crl_check` against the stale CRL still says `OK`
   until `nextUpdate` passes — this is the freshness-lag hole in §4.
2. Generate a **delta CRL** (`crlnumber` + `-crldelta`) and confirm it lists
   only the newly-revoked serial, not the full set.
3. Revoke a cert with `-crl_reason certificateHold`, regenerate, then "unhold"
   it (reason `removeFromCRL` via delta) and verify the status flips back.
4. Use `-crl_check_all` to force revocation checking up the *entire* chain (not
   just the leaf) and observe the difference.
5. Capture the OCSP request/response on the wire (`tcpdump`/Wireshark) and
   identify the `CertID` (issuerNameHash, issuerKeyHash, serialNumber).
6. In a FreeRADIUS test setup, enable `check_crl = yes` in the EAP `tls` block,
   point it at your CRL, and confirm EAP-TLS auth for the revoked client cert
   is rejected. Then simulate the "network kill switch": leave the cert valid
   but disable the user and send a CoA Disconnect.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. If an attacker steals a private key and can MITM the victim, why does
soft-fail OCSP provide essentially zero protection?**
Because the attacker is *already on the path*. Revocation only helps in exactly
the MITM scenario — and in that scenario the attacker simply drops the client's
OCSP query (or returns nothing). The client times out and **soft-fails**,
treating the revoked cert as valid. So the defense fails precisely when it's
needed. The only fixes are hard-fail (operationally unacceptable for the open
web), must-staple (rare), or pushed revocation sets like CRLSets/CRLite — or
just not relying on revocation and using short lifetimes.

**Q2. A cert was revoked 30 seconds ago but clients still accept it. Give two
independent reasons.**
(1) **CRL freshness lag** — the previously published CRL is still within its
`nextUpdate` window and is cached by RPs; your revocation won't appear until the
next CRL is generated and the caches expire. (2) **OCSP response caching** — a
previously fetched `good` OCSP response (or a stapled one) is still within its
`nextUpdate` and is reused. Revocation latency is bounded by your *publication
cadence and cache TTLs*, not by the instant you click "revoke."

**Q3. Why is `certificateHold` treated as special/dangerous, and why is it
banned for public TLS?**
It's the only *reversible* revocation state. That breaks the foundational
assumption that "revoked is permanent" — a relying party that saw `revoked` and
hard-failed can't safely cache that decision, because the cert might be
un-held later (`removeFromCRL`). It also enables abuse (suspend/resume games).
The CA/Browser Forum therefore prohibits suspension for publicly-trusted TLS
certs; once revoked, it stays revoked.

**Q4. OCSP fixed CRL size; what new problem did it introduce, and how does
stapling solve it?**
OCSP introduced a **privacy leak and a latency/availability dependency**: every
handshake triggers a per-cert query to a third-party (usually the CA),
revealing the user's browsing to the responder and adding a round-trip on the
critical path. **Stapling** moves the fetch to the *server*: the server gets a
fresh CA-signed OCSP response for its own cert and includes it in the
handshake. No client→CA query (no privacy leak), no extra round-trip, and the
staple can't be forged. The residual gap is that a plain staple is strippable —
which `Must-Staple` closes by mandating it.

**Q5. The CA can answer `good` for a serial it never issued. Why, and why does
it matter?**
Classic OCSP responders are often driven off a CRL: "is this serial on the
revoked list? No → `good`." A serial that was *never issued* is also "not on the
list," so it returns `good`. This matters because `good` doesn't actually prove
*issuance* — only *non-revocation*. RFC 6960 lets a responder assert
"unknown/not issued" via the extended revoked response, and high-assurance
responders should be authoritative (positive issuance check) rather than
CRL-derived.

**Q6. Why are short-lived certificates considered a *replacement* for
revocation rather than a complement?**
Revocation's whole job is to shrink the window during which a compromised cert
is trusted. A short-lived cert bounds that window *by construction* — if it
lives 1 hour, the worst-case exposure is ~1 hour, which is often *faster* than
real-world CRL/OCSP propagation would have achieved anyway. So you get the
security outcome of revocation without the fragile distribution machinery. The
catch is that short lifetimes are only viable with full automation (ACME, CLM),
which is why the two topics are joined at the hip.

**Q7. In EAP-TLS, who is the relying party for the client certificate, and why
do network teams often prefer a non-PKI kill switch?**
The **RADIUS/EAP server** is the relying party — it validates the client cert
during the TLS-in-EAP handshake. Network teams prefer the network layer because
it's **instant and authoritative**: disabling the user in the IdP makes the very
next authentication fail with zero CRL/OCSP propagation delay, and a **CoA
Disconnect-Message (RFC 5176)** tears down the *current* session immediately.
CRL/OCSP would leave an active session running until re-auth and could lag by
hours. PKI revocation becomes a backstop; the operational control plane is
RADIUS policy + CoA, often combined with short-lived auto-renewed device certs
(the SecureW2 model).

**Q8. Why did Chrome effectively stop doing live OCSP/CRL checks for leaf
certs?**
Because live checks were *both* ineffective (soft-fail) *and* costly (latency,
privacy, responder outages). Instead Google ships a curated, pushed revocation
dataset (CRLSets, conceptually similar to Mozilla's CRLite) bundled with the
browser — high-value revocations (CA compromises, major mis-issuance) are
distributed proactively and checked locally with no network round-trip and no
soft-fail. It's not comprehensive, but it's reliable for the revocations that
matter most, which is a better trade than unreliable universal checking.

➡ Next: [Day 11 — Certificate Lifecycle Management (CLM) at Scale](day-11-clm-automation-discovery.md)
