# Day 05 — CA Hierarchy & Chain of Trust

## THEORY

### 1. Why hierarchies exist at all

A Certificate Authority's whole value is its **private signing key**. If that key leaks, every certificate it ever issued is suspect and you must rebuild trust from scratch — re-distributing a new root to every device on earth. So PKI design is fundamentally about **protecting the most valuable key while still issuing certificates at scale**. Hierarchies solve this by separating the *trust anchor* (rarely used, heavily guarded) from the *workhorse* (online, issuing thousands of certs).

The trade-off is **blast radius vs. operational convenience**:

| Tier model | Structure | When to use | Blast radius if issuer compromised |
|------------|-----------|-------------|-----------------------------------|
| **Single-tier** | Root *is* the issuing CA | Labs, tiny internal, short-lived test PKI | Catastrophic — must replace the root everywhere |
| **Two-tier** | Offline root → online issuing CA | The standard for most enterprises | Revoke/replace the intermediate; root & all trust intact |
| **Three-tier** | Offline root → offline policy CA → online issuing CAs | Large orgs, multiple regions/business units, strict policy separation | Contained to one issuing CA; policy layer enforces segmentation |

The dominant real-world choice is **two-tier**. Three-tier adds a *policy CA* layer mainly for organizational/policy delegation, not extra cryptographic security.

### 2. Root vs. intermediate/issuing/subordinate

- **Root CA** — self-signed (Issuer == Subject), at the top. Its certificate is the **trust anchor**: it is trusted *because it's in the trust store*, not because anything vouches for it. There is nothing above it to verify its signature.
- **Intermediate / subordinate / issuing CA** — signed *by* the root (or by a higher CA). "Subordinate" is the generic term; "issuing CA" specifically means the subordinate that actually signs leaf/end-entity certs; "intermediate" is any CA between root and leaf. All carry `BasicConstraints: CA:TRUE`.
- **Leaf / end-entity** — server, client, device, user. `CA:FALSE`. This is the EAP-TLS client cert, the TLS server cert, etc.

### 3. Why the root is kept OFFLINE

The root signs *very rarely* — only to issue/renew intermediate CA certs and to sign CRLs covering its subordinates. So it does not need to be online. Best practice: the root key lives in an **HSM**, on an **air-gapped** machine, powered off and locked in a safe, brought out only for a ceremony (witnessed, logged, dual-control). Benefits:

- **Massively reduced attack surface** — a key that's never network-connected can't be remotely stolen.
- **Containment** — if the *online* issuing CA is compromised, you revoke that intermediate, stand up a new one signed by the still-trusted root, and re-issue leaves. **Devices keep trusting the root** — no painful root re-distribution.
- **Long validity** — roots commonly live 20–30 years (since changing them is so disruptive), while issuing CAs rotate every few years.

> **SecureW2 / managed PKI context:** A SecureW2 Managed PKI follows exactly this pattern — an **offline root** held securely, and a **cloud-hosted issuing CA** that signs the EAP-TLS device/user certs at scale. Cloud RADIUS validates leaf certs up to that issuing CA, and the issuing CA chains to the offline root that's been pushed to the device trust stores. Compromise of the cloud issuing CA is recoverable without re-trusting every enrolled device.

### 4. The cert that proves it's a CA: BasicConstraints & path length

Two extensions gate CA behavior:

- **`BasicConstraints`** — `CA:TRUE` means "this cert may sign other certs." A leaf with `CA:FALSE` (or no `pathlen` capacity) that tries to sign others MUST be rejected by validators.
- **`pathLenConstraint`** — the maximum number of **non-self-issued intermediate CAs** that may follow this CA in a valid chain. `pathlen:0` = "this CA may issue end-entity certs but **no further sub-CAs**." A root with `pathlen:1` permits one intermediate beneath it, then leaves.

```
Root      CA:TRUE, pathlen:1
  └─ Issuing CA   CA:TRUE, pathlen:0   <- may sign leaves, but NOT another sub-CA
        └─ Leaf   CA:FALSE
```

> **Gotcha:** path length counts intermediates *below* the constrained CA, not including the leaf and not counting self-issued (renewal) certs. Get this wrong and either you can't build the sub-CA you need, or you've left the hierarchy too permissive.

Also critical: **Key Usage** on a CA cert must include `keyCertSign` (and usually `cRLSign`). Missing `keyCertSign` = the cert can't validly sign certificates even if `CA:TRUE`.

### 5. How a chain is built and validated

Validation is two distinct phases. People conflate them and then can't debug failures.

**Phase 1 — Path building** (find a candidate chain from leaf up to a trust anchor):
- Match each cert's **Issuer DN** to a candidate's **Subject DN**, and — more reliably — match **AKI (Authority Key Identifier)** of the child to the **SKI (Subject Key Identifier)** of the parent. AKI/SKI matching disambiguates when multiple certs share a DN (e.g., during cross-signing or key rollover).
- If a needed intermediate is missing locally, the validator may **chase the AIA (Authority Information Access)** extension's `CA Issuers` URL to fetch it.
- Path building can produce **multiple** candidate paths (this is why cross-signing works — see §8).

**Phase 2 — Path validation** (verify the candidate chain):
1. **Signature** of each cert verifies with the **public key of the cert above it**, up to a trust anchor in the store.
2. **Validity dates** (`notBefore`/`notAfter`) of every cert in the chain are currently valid.
3. **BasicConstraints / pathLen** are satisfied at each level.
4. **Key Usage / EKU** are appropriate (e.g., issuing certs have `keyCertSign`; a client cert for EAP-TLS has EKU `clientAuth`).
5. **Name constraints** (if present) are satisfied (§9).
6. **Revocation** — not revoked per CRL/OCSP.
7. Terminates at a **trusted root** (trust anchor). The root's own signature is *not* checked (it's self-signed); it's trusted because it's in the store.

> The leaf is presented by the peer; the trust anchor is in *your* store; the intermediates can come from either. The job is to connect them.

### 6. Chain order in TLS, and the classic failures

In TLS the server sends a `Certificate` message containing its leaf **plus the intermediates** (it should NOT send the root — the client already has it). Per spec the order is **leaf first, then each issuing CA in order toward the root**. Modern TLS 1.3 stacks are lenient about order, but many older clients/devices are not.

Classic real-world failures:

- **Incomplete chain** — server sends only the leaf, omits the intermediate. Works in browsers that cache the intermediate or do AIA chasing; **fails** on strict clients (Java, many supplicants, mobile). Symptom: "works on my machine, fails on the phone." Fix: serve the **fullchain** (leaf + intermediate).
- **Misordered chain** — leaf not first, or out of order. Strict parsers reject.
- **Wrong/extra root included** — sending the root wastes bytes and can confuse some validators; harmless to most but considered incorrect.
- **Expired intermediate** — the leaf is fine but a CA above it expired → whole chain invalid (§10).

> **Why intermediate caching saves browsers but bites RADIUS:** Browsers cache previously-seen intermediates and chase AIA, so a missing intermediate often "works." A RADIUS supplicant / EAP-TLS client typically does **neither** — it validates strictly against a pinned chain. This is the #1 cause of "my Wi-Fi cert works in the browser but auth fails." Always provision the full intermediate chain to the supplicant.

### 7. AIA chasing & intermediate caching

- **AIA (Authority Information Access)** extension on a cert carries a `CA Issuers` URL pointing to the parent CA cert, and an OCSP responder URL. Validators that hit a missing intermediate can fetch it from `CA Issuers`. This is "AIA chasing."
- It's a **safety net, not a substitute** for serving the chain — AIA fetch may be blocked (offline, captive portal, firewalled), adds latency, and isn't done by all clients. Provision chains explicitly.

### 8. Cross-signing & bridging

A single certificate (one key, one subject) can be signed by **two different issuers**, producing two certs with the same subject/key but different signatures. This lets a CA be trusted via **multiple paths** simultaneously — old and new roots can both validate it during a transition.

- **Let's Encrypt example:** ISRG Root X1 was new and not yet in older device trust stores, so LE's intermediate was **cross-signed by the older, widely-trusted IdenTrust DST Root CA X3**. Old Android devices validated via the IdenTrust path; modern devices via ISRG Root X1. Same leaf, two valid chains — path building picks whichever ends at a trust anchor the client has.
- **Bridge CA:** instead of one root above all, independent PKIs cross-certify a central **bridge CA**, creating a mesh of trust (used by federations like the US Federal PKI). Path building becomes graph search rather than a simple chain.
- **Use for root rollover:** when introducing a new root, cross-sign the new intermediate with the old root so existing devices keep working while the new root propagates.

### 9. Name constraints — fencing in a delegated/internal CA

`NameConstraints` (set on a CA cert) restricts the namespaces a subordinate may issue for — `permittedSubtrees` and `excludedSubtrees` over DNS names, IP ranges, email, DNs.

```
Issuing CA NameConstraints:
  permitted: DNS:.corp.example.com, email:.corp.example.com
  excluded:  DNS:.bank.example.com
```

That issuing CA can mint certs for `*.corp.example.com` but is *cryptographically incapable* of issuing a valid `www.google.com` or anything under `bank.example.com`. This is how you safely delegate issuance to a business unit or an internal/managed CA without giving it the power to impersonate the whole internet. Public CAs and enterprises use name constraints to **contain** a sub-CA's authority. (Caveat: enforcement depends on the validator honoring the extension — most modern stacks do; mark it **critical**.)

### 10. What happens when an intermediate expires

The leaf can be perfectly valid and unexpired, but if **any** CA above it has passed `notAfter`, path validation fails at that link — the entire chain is invalid. This is a recurring outage cause (e.g., the AddTrust/Sectigo 2020 root expiry broke many services). Mitigations:

- **Plan renewals** so intermediates are renewed/rolled *well before* expiry, and push the new intermediate to all chains.
- **Cross-sign** the renewed intermediate to keep old paths valid during transition.
- **Monitor expiry** of every CA in the hierarchy, not just leaves.
- Note that an expired intermediate cert can be re-issued (new cert, **same key**) by the still-valid root — the leaves under it remain verifiable once the fresh intermediate is distributed.

---

## PRACTICE

```bash
# ============================================================
# Build a 2-tier CA: offline-style Root -> Issuing CA -> Leaf
# (single directory demo; in production the root key lives in an HSM, air-gapped)
# ============================================================

# --- 1. ROOT CA: self-signed, CA:TRUE, pathlen:1, long-lived ---
openssl ecparam -name prime256v1 -genkey -noout -out root.key
openssl req -x509 -new -key root.key -sha256 -days 7300 \
  -subj "/CN=SecureW2 Lab Root CA/O=SecureW2 Lab" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -out root.crt
```

```bash
# --- 2. ISSUING (intermediate) CA: CSR -> signed by root, CA:TRUE, pathlen:0 ---
openssl ecparam -name prime256v1 -genkey -noout -out issuing.key
openssl req -new -key issuing.key -sha256 \
  -subj "/CN=SecureW2 Lab Issuing CA/O=SecureW2 Lab" \
  -out issuing.csr

# Extensions applied at signing time (issuer controls what it grants):
cat > issuing.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
nameConstraints=critical,permitted;DNS:.corp.example,permitted;email:.corp.example
EOF

openssl x509 -req -in issuing.csr -CA root.crt -CAkey root.key \
  -CAcreateserial -days 3650 -sha256 \
  -extfile issuing.ext -out issuing.crt
```

```bash
# --- 3. LEAF (EAP-TLS client / device cert): CA:FALSE, clientAuth EKU ---
openssl ecparam -name prime256v1 -genkey -noout -out leaf.key
openssl req -new -key leaf.key -sha256 \
  -subj "/CN=device01.corp.example/O=SecureW2 Lab" -out leaf.csr

cat > leaf.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=DNS:device01.corp.example
authorityKeyIdentifier=keyid:always
EOF

openssl x509 -req -in leaf.csr -CA issuing.crt -CAkey issuing.key \
  -CAcreateserial -days 365 -sha256 -extfile leaf.ext -out leaf.crt
```

```bash
# --- 4. Inspect SKI/AKI linkage and constraints ---
openssl x509 -in root.crt    -noout -text | grep -A1 "Subject Key Identifier"
openssl x509 -in issuing.crt -noout -text | grep -A1 -E "Authority Key Identifier|Subject Key Identifier|Name Constraints|pathlen"
openssl x509 -in leaf.crt    -noout -text | grep -A1 "Authority Key Identifier"
# The leaf's AKI should equal the issuing CA's SKI; issuing CA's AKI == root's SKI.
```

```bash
# --- 5. Verify the chain (this is the success case) ---
# Build the intermediate bundle that a TLS server / supplicant should present (leaf + issuing)
cat leaf.crt issuing.crt > fullchain.pem

# Verify leaf, supplying the intermediate via -untrusted and the root as the trust anchor
openssl verify -CAfile root.crt -untrusted issuing.crt leaf.crt
# Expect: leaf.crt: OK

# Show the chain OpenSSL actually built
openssl verify -show_chain -CAfile root.crt -untrusted issuing.crt leaf.crt
```

```bash
# --- 6. Simulate BROKEN chains and read the errors ---
# (a) Missing intermediate -> path can't reach the root
openssl verify -CAfile root.crt leaf.crt
# Expect: "unable to get local issuer certificate"

# (b) Wrong trust anchor (treat the issuing CA as the only trusted root)
openssl verify -CAfile issuing.crt leaf.crt
# Fails to terminate at a trusted self-signed root (issuing.crt isn't self-signed/trusted here)

# (c) Name-constraint violation: issue a leaf OUTSIDE permitted subtree
openssl req -new -key leaf.key -subj "/CN=evil.bank.example" -out evil.csr
printf 'basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:evil.bank.example\n' > evil.ext
openssl x509 -req -in evil.csr -CA issuing.crt -CAkey issuing.key \
  -CAcreateserial -days 365 -sha256 -extfile evil.ext -out evil.crt
openssl verify -CAfile root.crt -untrusted issuing.crt evil.crt
# Expect a name-constraint failure: the issuing CA may not issue outside .corp.example
```

**Exercises:**
1. Build the full 2-tier CA above, then prove with `openssl x509` that the leaf's AKI equals the issuing CA's SKI and the issuing CA's AKI equals the root's SKI. Explain why AKI/SKI matching is more robust than DN matching during path building.
2. Set the issuing CA's `pathlen:0`, then try to sign *another* sub-CA under it and verify the chain — confirm validators reject it. Explain what `pathlen` counts.
3. Reproduce the "missing intermediate" failure, then fix it by serving `fullchain.pem`. Relate this to why an EAP-TLS supplicant fails where a browser succeeds.
4. Trigger a name-constraints violation (issue for `bank.example`) and capture the exact OpenSSL error. Argue why name constraints make delegating an internal/issuing CA safe.
5. Simulate an expired intermediate (issue `issuing.crt` with `-days 1`, or backdate), then verify a still-valid leaf and observe the whole-chain failure. Describe two mitigations (cross-sign, proactive renewal).
6. Cross-signing thought experiment: you stand up a new root and must keep old devices working. Describe, with cert subjects/keys, how you'd cross-sign the issuing CA so both the old and new roots produce a valid path — referencing the Let's Encrypt / IdenTrust DST X3 example.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why keep the root CA offline if it just means more operational hassle?**
Because the root is the **irreplaceable trust anchor** — it's baked into every device's trust store, and replacing it means re-distributing trust to the entire fleet, which is enormously painful. Keeping it offline (air-gapped, HSM, powered down, dual-control ceremonies) means it has essentially no remote attack surface. If the *online* issuing CA is breached, you revoke that intermediate, the offline root signs a fresh one, and **every device keeps trusting the same root** — no re-distribution. The hassle of offline operation buys you a recoverable compromise instead of a catastrophic one.

**Q2. A cert works in Chrome but EAP-TLS authentication fails on the same network. Most likely cause?**
Incomplete chain. Browsers cache previously-seen intermediates and perform AIA chasing, so a server that omits its intermediate still "works." A Wi-Fi supplicant/RADIUS client usually does **neither** — it validates strictly against the chain it's given. The server (or provisioning) is sending only the leaf without the intermediate(s). Fix by serving the **fullchain** (leaf + all intermediates, leaf first) to the supplicant. This is the single most common EAP-TLS chain bug.

**Q3. What's the difference between path building and path validation, and why does it matter?**
Path **building** is the search for a candidate chain from the leaf up to *some* trust anchor — using Issuer/Subject DN and AKI/SKI matching, possibly AIA-fetching missing intermediates, possibly finding multiple candidate paths (e.g., cross-signed). Path **validation** then verifies a candidate: signatures, validity dates, basic constraints/pathlen, key usage/EKU, name constraints, revocation, and termination at a trusted root. It matters because failures differ: "unable to get local issuer" is a *building* failure (can't find the path), whereas "certificate expired" or "name constraint violated" is a *validation* failure on a path that was found.

**Q4. The leaf is valid and unexpired but TLS still fails with an expiry error. How?**
An intermediate or root **above** the leaf has expired. The chain is only as valid as its weakest link — every cert from leaf to trust anchor must currently be within its `notBefore`/`notAfter`. This caused real outages (e.g., the 2020 AddTrust/Sectigo root expiry). The leaf being valid is necessary but not sufficient. Remedy: re-issue the intermediate (same key, new validity) from the still-valid root and re-distribute the chain; cross-sign to ease transition; and monitor expiry of *every* CA, not just leaves.

**Q5. Explain cross-signing using the Let's Encrypt example. Why have two certs for one key?**
Cross-signing means the same intermediate (same key/subject) is signed by **two different roots**, yielding two certs with different signatures and thus two valid paths. Let's Encrypt's ISRG Root X1 wasn't yet present in older Android trust stores, so LE cross-signed its intermediate with the long-trusted **IdenTrust DST Root CA X3**. Old devices validated through the IdenTrust path; modern devices through ISRG Root X1. The single leaf can satisfy clients with different trust stores because path building selects whichever path ends at a root the client actually trusts. It's the standard technique for introducing a new root without breaking legacy clients.

**Q6. How would you delegate an issuing CA to a business unit without letting them impersonate arbitrary domains?**
Put **NameConstraints** (marked critical) on their subordinate CA cert — `permittedSubtrees` limited to their namespace (e.g., `DNS:.bu.corp.example`) and `excludedSubtrees` for anything sensitive. The sub-CA then cannot mint a *valid* cert outside that namespace; conforming validators reject any leaf that escapes the permitted subtree. Combine with a tight `pathlen` (often `pathlen:0` so they can't spawn further sub-CAs). This is cryptographic containment of delegated authority — the foundation for safely running internal/regional/managed issuing CAs.

**Q7. What does `pathlen:0` on an issuing CA actually permit and forbid?**
`pathlen:0` means **zero additional CA certificates may appear below this one** in a valid path — i.e., it may issue end-entity (leaf) certs but **not** another subordinate CA. It counts non-self-issued intermediates beneath the constrained CA, not the leaf and not self-issued renewals. A root with `pathlen:1` permits exactly one intermediate, then leaves. Misconfiguring this either blocks a sub-CA you legitimately need or leaves the hierarchy too permissive (an issuing CA able to delegate further than intended).

**Q8. Why must a CA cert have both `CA:TRUE` and `keyCertSign`, and what breaks if one is missing?**
`BasicConstraints: CA:TRUE` authorizes the cert to be an issuer in path validation; `KeyUsage: keyCertSign` authorizes its key to sign certificates (and `cRLSign` to sign CRLs). A conforming validator requires **both** — a `CA:TRUE` cert lacking `keyCertSign` cannot validly sign certs, and a cert with `keyCertSign` but `CA:FALSE` fails the basic-constraints check. If either is missing, the chain breaks at that link with a usage/constraint error even though the signature math is fine. This is why "I signed a leaf with my server cert and it doesn't validate" — the server cert was `CA:FALSE`.

**Q9. When would you actually choose three-tier over two-tier?**
When you need **organizational/policy separation**, not extra cryptographic strength. A three-tier model inserts an offline **policy CA** between the root and the online issuing CAs so multiple issuing CAs (per region, per business unit, per policy/assurance level) can be governed and revoked independently while the root signs only the policy CA. It's justified for large, federated, or compliance-heavy environments. For most enterprises — including a typical managed cloud PKI for passwordless Wi-Fi — **two-tier (offline root + online issuing CA) is sufficient**; three-tier just adds operational overhead unless the policy segmentation is genuinely required.

➡ Next: [Day 06 — Keys, CSRs, HSMs & Key Management](day-06-keys-csr-hsm-key-management.md)
