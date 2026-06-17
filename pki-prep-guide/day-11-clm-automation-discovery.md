# Day 11 — Certificate Lifecycle Management (CLM) at Scale

## THEORY

### 1. What a CLM platform actually does

Once you have more than a handful of certificates, the bottleneck stops being
"can I issue a cert?" and becomes "do I even know how many I have, where they
are, and when each one dies?" **Certificate Lifecycle Management (CLM)** is the
discipline (and the tooling) of managing every certificate from cradle to grave.

The core capabilities, in the order they bite you in production:

- **Discovery** — find certs you didn't know existed (network scans, endpoint
  agents, CA/cloud integrations). You can't manage what you can't see.
- **Inventory** — a single authoritative store: subject, SANs, issuer, key
  algorithm/size, validity, location (host:port, key store, secrets manager),
  owner, and purpose. This is the system of record.
- **Automated enrollment** — issue certs programmatically (ACME, SCEP, EST,
  REST APIs, cloud CA integrations) instead of humans pasting CSRs.
- **Automated renewal** — re-issue and **deploy** before expiry, with no human
  in the loop. Renewal without *deployment* is a half-solution.
- **Policy enforcement** — reject weak keys (RSA-1024, SHA-1), enforce allowed
  CAs, key usages, validity caps, naming, and approved crypto.
- **Expiry prevention / alerting** — proactive warnings (90/30/7 days), tiered
  to owners and escalation paths.
- **Reporting & audit** — compliance evidence, who-issued-what, algorithm
  inventory for crypto-agility planning.

> **Why this is a *category*, not a feature:** issuance is a 5-minute problem;
> *operating* tens of thousands of identities across servers, load balancers,
> mobile devices, IoT, containers, and clouds — each with its own enrollment
> protocol and renewal cadence — is the actual hard problem.

### 2. The "unknown certificates" problem (sprawl & shadow certs)

The number one cause of certificate outages is **expiry of a cert nobody knew
they owned.** How sprawl happens:

- A developer spins up a service and grabs a cert "just to ship," off the books.
- Self-signed and internal-CA certs proliferate on load balancers, app servers,
  message brokers, and microservices.
- Cloud auto-provisioning mints certs faster than any spreadsheet can track.
- Wildcard certs get copied across dozens of hosts; one revocation/expiry takes
  them all down at once.

These are **shadow certificates**: real, trusted, in-production, and *invisible
to the team responsible for them.* When one expires at 2am, the outage is total
and the on-call has no idea which cert, on which host, in which key store. CLM's
**discovery** function exists specifically to drag these into the light.

### 3. Discovery methods

| Method | How it works | Strengths | Blind spots |
|--------|--------------|-----------|-------------|
| **Network scanning** | Connect to host:port ranges, do a TLS handshake, read the presented cert | Agentless, finds *deployed* certs incl. shadow ones | Misses certs not yet bound to a listener; firewall-limited; only sees what's on the wire |
| **Agent-based** | Endpoint agent enumerates local key/trust stores (Windows store, Java keystore, NSS, PEM dirs) | Finds installed-but-unbound certs and private-key locations | Deployment/maintenance burden; coverage gaps where no agent |
| **CA integration** | Pull issued-cert logs directly from the CA(s) | Authoritative issuance record | Only certs from *known* CAs; misses external/self-signed |
| **ACME / protocol hooks** | Observe enrollment via ACME, SCEP, EST | Real-time, automated, captures renewals | Only protocol-managed certs |
| **Cloud / platform APIs** | Query AWS ACM, Azure Key Vault, GCP, Kubernetes secrets, load balancers, CDNs | Sees managed/cloud certs at scale | Per-platform integration effort |
| **CT log monitoring** | Watch Certificate Transparency logs for your domains | Catches *publicly* issued certs (incl. rogue) | Public TLS only; nothing internal |

Mature CLM uses **several methods together** — no single one is complete.

### 4. Crypto-agility

**Crypto-agility** is the ability to change cryptographic primitives — algorithm,
key size, hash, or even the issuing CA — **quickly and at scale**, without
re-architecting. Why it suddenly matters:

- **Algorithm deprecation** — SHA-1 → SHA-256 migrations, RSA-1024 → 2048/3072,
  and the move to ECDSA were each multi-year scrambles for organizations
  without an inventory.
- **Post-quantum (PQC) transition** — the looming big one. NIST has standardized
  PQC algorithms (ML-DSA/ML-KEM); organizations will need to swap signature and
  key-exchange algorithms across their entire certificate estate. If you can't
  even *enumerate* your certs and their algorithms, you cannot plan a PQC
  migration. CLM inventory + automated re-issuance is the prerequisite.
- **CA migration / distrust events** — when a CA is distrusted (it has happened
  to major CAs), every cert from that CA must be re-issued *fast*. With CLM and
  **CA-agnostic** management this is a policy change + bulk renewal; without it,
  it's a fire drill.

> **Practitioner truth:** crypto-agility isn't a crypto problem, it's an
> *inventory + automation* problem. The math is easy; finding and re-issuing
> 40,000 certs across 12 platforms is the hard part.

### 5. The cost of expiry outages (real examples)

Expired certs cause spectacular, expensive outages — and they're 100%
preventable:

- **Microsoft Azure / Teams** outages traced to expired certificates.
- **Microsoft Exchange (2018)** — an expired cert broke Office/365 voicemail
  and other services.
- **LinkedIn, Spotify, Ericsson (2018)** — an expired certificate in Ericsson
  software knocked out mobile data for tens of millions of O2/SoftBank users.
- **Equifax (2017)** — an expired cert on a monitoring device left an
  intrusion-detection system blind for ~19 months, contributing to the famous
  breach going undetected.
- Routine but painful: expired internal/API certs breaking payment processing,
  CI/CD pipelines, and service-to-service auth.

The lesson interviewers want: **outages from expiry are operational failures,
not cryptographic ones**, and the fix is automation + inventory, not "remember
better."

### 6. CA-agnostic management & DevOps/secrets integration

- **CA-agnostic** — a good CLM platform brokers across multiple CAs (public:
  DigiCert/Sectigo/Let's Encrypt; private: Microsoft ADCS, EJBCA, cloud CAs).
  Benefits: no lock-in, fast CA failover, mix public + private under one policy.
- **DevOps integration** — certs are requested *as code*: Terraform providers,
  Kubernetes cert-manager (ACME/issuer CRDs), Jenkins/GitLab pipelines,
  Ansible. The cert lifecycle becomes part of the deployment lifecycle.
- **Secrets-manager integration** — private keys and certs land in
  HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, CyberArk — not on
  disk, not in a wiki. The CLM orchestrates issuance/renewal and pushes the
  material into the secrets store, which controls access and rotation.

### 7. Machine identity management (the category)

The framing the industry now uses: every workload, device, service, container,
and bot needs an **identity**, and certificates are the dominant machine
credential. **Machine Identity Management (MIM)** is the umbrella discipline —
CLM is its certificate arm. The driver is scale: machine identities now vastly
outnumber human identities, churn faster (containers live seconds), and can't
"call the help desk." Automation is mandatory, which loops back to short-lived
certs (Day 10) and CLM.

### 8. CLM vendors — conceptual comparison

You don't need product trivia, but you should be able to place the players:

| Vendor / approach | Conceptual positioning |
|-------------------|------------------------|
| **Venafi** | Pioneered the "machine identity management" framing; deep enterprise CLM, policy, large-scale TLS machine identity governance. |
| **Keyfactor** | CLM + PKI-as-a-service + IoT/device identity; strong on bringing your own CA and embedding identity into devices. |
| **AppViewX** | CLM + network/ADC automation (CERT+ / AVX ONE); strong app-delivery and orchestration heritage. |
| **DigiCert** | A public CA that also offers CLM (CertCentral / Trust Lifecycle Manager) — manage *and* issue from one vendor. |
| **SecureW2** | **Managed PKI focused on device-certificate lifecycle for passwordless network access.** Auto-enrolls device certs via MDM/SCEP/onboarding, **auto-renews** them, ties cert validity to IdP entitlement, and feeds the certs into EAP-TLS so users authenticate to Wi-Fi/VPN with no passwords. The lifecycle is invisible to the end user and to the help desk. |

**Where SecureW2 fits the story:** instead of operators manually tracking and
renewing thousands of device certs, the managed PKI enrolls a per-device cert
during onboarding (gated by the IdP), renews it automatically before expiry, and
revokes/lets-it-lapse the moment the user/device is deprovisioned in the IdP.
This is CLM specialized for the **network-access** use case: it solves expiry
(auto-renew), discovery (the platform *is* the issuer of record), and revocation
(IdP-tied + short-lived + CoA, per Day 10) in one closed loop — which is exactly
why passwordless EAP-TLS at scale is operationally feasible.

### 9. Putting it together — the closed loop

```
 Discover ──► Inventory ──► Policy check ──► Enroll/Issue
    ▲                                              │
    │                                              ▼
 Report ◄── Alert/Audit ◄── Monitor expiry ◄── Deploy to host/secret store
                                   │
                                   └─► Auto-renew (before notAfter) ─┐
                                                                      │
                                       (loop continuously) ◄──────────┘
```

The whole point is that this loop runs **without humans**, which is what makes
short-lived certs (Day 10) and zero-touch passwordless access practical.

---

## PRACTICE

```bash
# ─────────────────────────────────────────────────────────────
# 1. A discovery script: scan host:port list, build a cert CSV
# ─────────────────────────────────────────────────────────────
cat > targets.txt <<'EOF'
google.com:443
github.com:443
badssl.com:443
expired.badssl.com:443
self-signed.badssl.com:443
EOF

cat > scan_certs.sh <<'EOF'
#!/usr/bin/env bash
# Usage: ./scan_certs.sh targets.txt > cert_inventory.csv
# Connects to each host:port, pulls the leaf cert, extracts key fields.
set -u
IN="${1:-targets.txt}"
NOW_EPOCH=$(date +%s)

echo "host,port,subject,issuer,not_before,not_after,days_left,sig_alg,key_bits,sans,status"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  host="${line%%:*}"; port="${line##*:}"

  # Grab the presented leaf cert (servername sets SNI). 5s connect timeout.
  cert=$(echo | timeout 8 openssl s_client -connect "$host:$port" \
           -servername "$host" 2>/dev/null \
         | openssl x509 2>/dev/null)

  if [ -z "$cert" ]; then
    echo "$host,$port,,,,,,,,,UNREACHABLE_OR_NO_CERT"
    continue
  fi

  subj=$(echo "$cert"  | openssl x509 -noout -subject | sed 's/^subject=//; s/,/ /g')
  iss=$(echo "$cert"   | openssl x509 -noout -issuer  | sed 's/^issuer=//;  s/,/ /g')
  nb=$(echo "$cert"    | openssl x509 -noout -startdate | cut -d= -f2)
  na=$(echo "$cert"    | openssl x509 -noout -enddate   | cut -d= -f2)
  sig=$(echo "$cert"   | openssl x509 -noout -text | awk -F': ' '/Signature Algorithm/{print $2; exit}')
  bits=$(echo "$cert"  | openssl x509 -noout -text | grep -oE 'Public-Key: \([0-9]+ bit\)' | grep -oE '[0-9]+' | head -1)
  sans=$(echo "$cert"  | openssl x509 -noout -ext subjectAltName 2>/dev/null \
         | grep -oE 'DNS:[^,]+' | paste -sd';' -)

  # days_left from notAfter
  na_epoch=$(date -d "$na" +%s 2>/dev/null || echo "$NOW_EPOCH")
  days_left=$(( (na_epoch - NOW_EPOCH) / 86400 ))

  status="OK"
  [ "$days_left" -lt 0 ]  && status="EXPIRED"
  [ "$days_left" -ge 0 ] && [ "$days_left" -le 30 ] && status="EXPIRING_SOON"

  echo "$host,$port,\"$subj\",\"$iss\",\"$nb\",\"$na\",$days_left,$sig,$bits,\"$sans\",$status"
done < "$IN"
EOF
chmod +x scan_certs.sh

./scan_certs.sh targets.txt | tee cert_inventory.csv

# ─────────────────────────────────────────────────────────────
# 2. Triage the inventory: what's expired / expiring / weak?
# ─────────────────────────────────────────────────────────────
# Expired or expiring within 30 days
awk -F, 'NR>1 && ($11 ~ /EXPIRED/ || $11 ~ /EXPIRING_SOON/)' cert_inventory.csv

# Weak crypto: SHA-1 signatures or RSA < 2048
awk -F, 'NR>1 && ($8 ~ /sha1/ || ($9 != "" && $9+0 < 2048))' cert_inventory.csv

# Algorithm inventory (crypto-agility planning input)
awk -F, 'NR>1 {print $8}' cert_inventory.csv | sort | uniq -c | sort -rn

# ─────────────────────────────────────────────────────────────
# 3. Single-host quick check (handy in incident response)
# ─────────────────────────────────────────────────────────────
HOST=expired.badssl.com
echo | openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# ─────────────────────────────────────────────────────────────
# 4. Conceptual automation pipeline (pseudo / cron-driven)
# ─────────────────────────────────────────────────────────────
cat > renew_pipeline.sh <<'EOF'
#!/usr/bin/env bash
# Sketch of a zero-touch renewal loop. In production this is a CLM platform;
# here it shows the control flow you should be able to describe.
THRESHOLD_DAYS=21
while IFS=, read -r host port _ _ _ _ days_left _ _ _ status; do
  [ "$host" = "host" ] && continue                 # skip header
  if [ "${days_left:-999}" -le "$THRESHOLD_DAYS" ]; then
    echo "[RENEW] $host:$port has $days_left days left -> triggering renewal"
    # 1. Request a new cert from the (CA-agnostic) issuer, e.g. ACME:
    #    certbot/acme.sh/cert-manager OR vendor API call
    # 2. Push key+cert into the secrets manager (Vault/ASM/AKV)
    # 3. Reload the service / rotate via orchestration (no downtime)
    # 4. Re-run discovery to confirm the NEW notAfter is live
    # 5. Record the action in the audit log
  fi
done < cert_inventory.csv
EOF
chmod +x renew_pipeline.sh
./renew_pipeline.sh

# Schedule discovery daily (cron) so the inventory never goes stale:
#   0 6 * * *  /path/scan_certs.sh /path/targets.txt > /path/cert_inventory.csv
```

**Exercises:**

1. Extend `scan_certs.sh` to also record the **CDP** and **OCSP (AIA)** URLs per
   cert, then cross-reference with Day 10's revocation lab.
2. Add SNI-less scanning vs SNI scanning for the same host and explain why the
   presented cert can differ (virtual hosting).
3. Feed a `/24` of internal IPs (e.g., via `nmap -p 443 --open`) into the
   scanner to *discover shadow certs* on hosts not in `targets.txt`.
4. Wire the "EXPIRING_SOON" rows into an alert (email/Slack webhook) and tier the
   thresholds at 90/30/7 days.
5. Write a tiny policy-check that **fails the pipeline** (non-zero exit) if any
   cert uses SHA-1 or RSA < 2048 — that's enforcement, not just reporting.
6. Model a PQC migration: add a `key_alg` column, then produce a report of which
   certs would need re-issuance to an ML-DSA cert, and estimate the renewal
   batch size.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. What is the single most common cause of certificate-related outages, and
why does throwing more monitoring at it not fully solve it?**
**Expiry of an unknown/unowned ("shadow") certificate.** More monitoring helps
*known* certs, but you can't alert on a cert you don't know exists. The root fix
is **discovery + inventory** (so every cert is known and owned) *plus*
**automated renewal** (so renewal doesn't depend on a human acting on the
alert). Alerting alone just tells you about the outage you're about to have.

**Q2. Why is crypto-agility fundamentally an inventory/automation problem rather
than a cryptography problem?**
Swapping an algorithm (SHA-1→SHA-256, RSA→ECDSA, classical→PQC) is trivial *per
cert* — the libraries already support it. The hard part is doing it across an
estate you may not fully see: you must **enumerate** every cert and its
algorithm, **locate** it (host, key store, secrets manager), and **re-issue +
redeploy** it without breaking the service. Organizations that fail PQC/SHA-1
migrations fail on inventory and deployment automation, not on the math.

**Q3. Discovery via network scanning misses certain certs. Which, and how do you
cover the gap?**
Network scanning only sees certs **bound to a live listener** at scan time — it
misses installed-but-unbound certs, certs in local key stores not yet deployed,
internal certs behind firewalls, and certs on hosts not in your target list. You
cover the gap by **combining methods**: agent-based store enumeration, direct
**CA issuance-log integration**, **cloud/platform API** queries (ACM, Key Vault,
k8s secrets), and **CT-log monitoring** for public issuance. No single method is
complete.

**Q4. What does "CA-agnostic" buy you, and when does it become business-critical
overnight?**
It avoids lock-in and lets one policy/inventory span multiple CAs (public +
private). It becomes critical the moment a **CA is distrusted** or has a mass
mis-issuance event: every cert from that CA must be re-issued *fast*. With
CA-agnostic CLM you flip the issuer in policy and bulk-renew; without it you're
hand-migrating thousands of certs to a new CA under time pressure during an
incident.

**Q5. An OCSP `good` response and a CLM inventory entry both say a cert is
"fine." What's the difference in what they actually assert?**
OCSP `good` asserts *non-revocation* at a point in time (and not even issuance,
necessarily — Day 10, Q5). A CLM inventory entry asserts **operational
knowledge**: that the cert is known, owned, located, policy-compliant, and
tracked for renewal. They answer different questions: OCSP = "should a relying
party trust it right now?"; CLM = "do *we* manage it and will it expire on us?"
A cert can be OCSP-`good` and still be a ticking outage if it's a shadow cert
nobody is renewing.

**Q6. Why are short-lived certs (Day 10) and CLM mutually dependent?**
Short-lived certs bound compromise/exposure windows but are **impossible to
manage by hand** — you cannot renew a 24-hour (let alone 1-hour) cert manually.
That forces full automation, i.e. CLM. Conversely, mature CLM makes short
lifetimes *cheap*, which lets you reduce reliance on fragile revocation. They
reinforce each other: automation enables short lifetimes; short lifetimes
justify the automation.

**Q7. How does SecureW2's managed PKI collapse discovery, renewal, and
revocation into one loop for network access?**
Because the platform **is the issuer of record** for device certs, discovery is
implicit — every device cert was enrolled through it (via MDM/SCEP/onboarding),
so there are no shadow device certs. **Renewal** is automatic before `notAfter`,
so users never hit an expiry-driven auth failure. **Revocation** is handled by
tying cert validity to **IdP entitlement** plus short lifetimes plus network-layer
CoA (Day 10): deprovision the user in the IdP and the next EAP-TLS auth fails and
the cert isn't renewed. One closed loop, invisible to the user and help desk —
which is what makes passwordless EAP-TLS feasible at thousands-of-devices scale.

**Q8. You join a company with "no idea how many certs we have." What are your
first three moves?**
(1) **Discover** — run multi-source discovery (network scan of known ranges +
CA issuance logs + cloud/k8s APIs + CT monitoring for your domains) to build an
initial inventory. (2) **Triage** — sort by *expired / expiring ≤30d* and *weak
crypto*, fix the imminent outages first, assign owners. (3) **Automate** — stand
up automated renewal (ACME/cert-manager/CLM) and a scheduled discovery job so
the inventory stays current, then layer policy enforcement (min key size, banned
algorithms, approved CAs). Stabilize the fires, then make the loop self-running.

➡ Next: [Day 12 — The TLS Handshake & Mutual TLS (mTLS)](day-12-tls-handshake-mtls.md)
