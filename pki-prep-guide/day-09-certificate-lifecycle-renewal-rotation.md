# Day 09 — The Certificate Lifecycle: Renewal, Rotation & Expiry

Yesterday you learned how a cert is *born*. Today you learn that a certificate is not an artifact — it's a **lease on trust with a hard expiry**, and every cert you issue is a future outage scheduled for a date you forgot to write down. The entire discipline of Certificate Lifecycle Management (CLM) exists because humans cannot reliably track thousands of expiry dates. This is the day that separates people who *issue* certs from people who *operate* PKI.

---

## THEORY

### 1. The full lifecycle

```
        ┌──────────┐   ┌────────┐   ┌─────────┐   ┌──────────┐   ┌──────────────┐
        │ REQUEST  │──►│ ISSUE  │──►│ DEPLOY  │──►│ MONITOR  │──►│ RENEW / REKEY │──┐
        └──────────┘   └────────┘   └─────────┘   └──────────┘   └──────────────┘  │
              ▲                                          │                          │
              │                                          ▼                          │
              │                                   ┌──────────────┐                  │
              └───────────────────────────────────│ REVOKE/EXPIRE│◄─────────────────┘
                                                   └──────────────┘
```

1. **Request** — keypair + CSR (Day 06–07).
2. **Issue** — RA validates, CA applies template, signs (Day 08).
3. **Deploy** — install on the endpoint (web server, RADIUS, device keystore/TPM).
4. **Monitor** — track expiry, key health, revocation status. *The step everyone skips.*
5. **Renew / rekey** — replace before expiry.
6. **Revoke / expire** — retire the cert (CRL/OCSP, Day 10) or let it lapse naturally.

The loop never stops. A cert that is "deployed and forgotten" is a landmine.

### 2. Renewal vs Rekey vs Reissue — know the difference

This is the single most-confused trio in PKI interviews. They are **not** synonyms.

| Operation | New keypair? | New validity? | When you use it |
|---|---|---|---|
| **Renewal** | ❌ same key reused | ✅ yes | Convenience extend; cert about to expire, key still fine |
| **Rekey** | ✅ brand-new keypair | ✅ yes | Best practice on every renewal; mandatory if key may be exposed |
| **Reissue / Replace** | maybe | resets/keeps | Fix a mistake (wrong SAN, wrong EKU) or post-incident replacement |

- **Renewal** — issue a new cert binding the **same public key** to a new validity window. Easy, but you carry forward any key risk and never rotate the key material.
- **Rekey** — generate a **fresh keypair** and issue a new cert for it. This *is* key rotation. After Heartbleed, "renew" without rekey was useless because the old private key was potentially exposed — you **must** rekey to actually be safe.
- **Reissue/Replace** — correct an error or respond to an incident; often paired with revoking the old cert.

> **Gotcha #1 — "I renewed the cert" after a key compromise is meaningless.** If the private key may be exposed, renewal that reuses the key changes nothing. You must **rekey** (new keypair) *and* **revoke** the old cert. Modern automated CLM rekeys on every cycle by default — treat reuse-of-key as the exception, not the norm.

### 3. The march toward shorter validity

Public TLS lifetimes have collapsed, deliberately:

| Era | Max TLS cert validity | Driver |
|---|---|---|
| pre-2015 | 5 years | — |
| 2015 | 39 months | CA/B Forum |
| 2018 | 825 days (~27 mo) | CA/B Forum |
| 2020 | **398 days** | Apple forced it unilaterally; others followed |
| 2026–2029 | **stepping to 47 days** | CA/B Forum ballot SC-081 (phased: ~200d → 100d → 47d) |
| trajectory | effectively ~automate-or-die | — |

**Why shorter is better:**
- **Revocation is unreliable** (CRLs are stale, OCSP soft-fails). A short lifetime is *implicit revocation* — a compromised cert self-destructs in weeks instead of years.
- **Limits the value of a stolen key** — less time to abuse it.
- **Forces hygiene** — domains/SANs that no longer belong to you drop off fast.
- **Forces automation** — which is the real goal; manual renewal at 47 days is impossible at scale.

> **Gotcha #2 — short lifetimes are a forcing function for automation, not a punishment.** The ecosystem is intentionally making manual cert management impossible so that everyone adopts ACME/SCEP/EST/CLM. If your renewal process involves a human and a calendar reminder, the 47-day world breaks you.

### 4. Automation is the only sane answer

At any real scale, the math is unforgiving: 10,000 device certs × annual renewal = ~27 renewals/day, *every day, forever.* No human team does that reliably. Protocols:

- **ACME** (RFC 8555) — public/internal TLS server auto-renewal (certbot, Caddy, internal ACME CAs).
- **SCEP** — classic device/MDM enrollment + renewal (still everywhere in MDM).
- **EST** (RFC 7030) — modern, TLS-based device enrollment/rekey.
- **CLM platforms** — SecureW2, Venafi, Microsoft Intune + AD CS connectors orchestrate enroll → monitor → auto-renew → revoke across the fleet.

> **SecureW2 tie-in:** JoinNow auto-renews managed device certs *before* expiry without user interaction — the device silently re-enrolls (rekey), the new cert lands in the keystore/TPM, and EAP-TLS never blinks. The whole point is that the user never sees a Wi-Fi disconnect because a cert rolled over. That only works if the renewal window and CLM are configured correctly.

### 5. Renewal windows & overlap

You never renew *at* expiry — you renew during a **window** before it, so the new cert overlaps the old:

```
  old cert valid ████████████████████████████░░░░░  expires
  renew window                          ┌──────┐
  new cert valid                        ███████████████████████  (overlaps old)
```

- **Renew at ~⅔ to ¾ of lifetime** (a 90-day cert → renew around day 60). For very short certs, even earlier.
- **Overlap** guarantees: if renewal fails, you have buffer to retry/alert before the old cert dies.
- **Stagger** renewals so the whole fleet doesn't expire on the same hour (correlated outage risk).

> **Gotcha #3 — renewing exactly at expiry has zero safety margin.** One failed renewal (network blip, IdP hiccup, ACME challenge fail) and you're in an outage. The overlap window is your retry budget. Make the window comfortably larger than your alert-and-respond time.

### 6. What breaks at expiry — and how it *looks*

Expiry failures are nasty because they're **silent until they're total**:

- **TLS server cert expires** → every client gets a hard `CERTIFICATE_EXPIRED` error. Total outage. Browsers won't click through for HSTS sites.
- **EAP-TLS client cert expires** → the device **silently drops off Wi-Fi/802.1X**. No popup, no error to the user — devices just stop authenticating and roam to nothing. Help desk gets "Wi-Fi is broken" with no clue it's a cert. *This is the SecureW2 nightmare scenario auto-renewal prevents.*
- **RADIUS server cert expires** → *every* EAP-TLS client rejects the server (or fails server validation) — mass auth failure across the whole site at once.
- **Intermediate CA expires** → **every leaf under it fails simultaneously**, even leaves that are still individually valid, because the chain can't be built. The most catastrophic and most overlooked.
- **Code-signing cert expires** → new signatures fail; existing signatures may survive *if* timestamped (timestamping decouples signature validity from cert validity).

> **Gotcha #4 — an expired intermediate kills valid leaves.** People monitor leaf certs and forget the intermediate that signs them. When the intermediate lapses, thousands of perfectly-valid leaves break at once with no individual cert having "expired." Always monitor the *whole chain*.

### 7. Monitoring & alerting

You cannot manage what you don't measure. A real CLM monitoring posture:

- **Inventory first** — you can't monitor certs you don't know exist. Discovery (scan hosts/ports, pull from CA databases) is step zero.
- **Track the whole chain** — leaf, intermediate, root expiry.
- **Tiered alerts** — e.g. warn at 30 days, escalate at 14, page at 7/3. Multiple thresholds because one alert gets ignored.
- **Dashboards** — expiry timeline, "expiring in next 30 days," per-owner breakdown.
- **Alert on *absence of renewal*, not just expiry** — if a cert that should auto-renew at day 60 hasn't by day 70, that's the real signal — far earlier than expiry.

### 8. Root / intermediate rotation planning

Rotating a root or intermediate is a **months-to-years** project, not a maintenance window:

- **Long lead time** — new root/intermediate must be distributed to **every trust store** (OS, browser, device, RADIUS NPS trusted-root config) *before* you start issuing under it. Trust-store propagation (OS/browser update cycles) is the bottleneck.
- **Cross-signing** — bridge old → new trust so relying parties trust the new hierarchy during migration without a flag-day.
- **Overlap the hierarchies** — run old and new in parallel; migrate leaves gradually; retire old only when nothing chains to it.
- **Plan well before expiry** — a root with 2 years left is *already* a planning item if propagation takes 12–18 months.

### 9. Key rollover

- **Server/leaf keys** — rotate on every rekey (cheap, automated).
- **CA keys** — rare, ceremonial, planned. Generate new CA keypair, cross-sign, migrate issuance, retire old key per a documented key-rollover plan. The `authorityKeyIdentifier`/`subjectKeyIdentifier` (AKI/SKI) extensions are what let relying parties pick the right key during overlap — this is why those extensions matter operationally.

### 10. War stories — expired intermediates take down giants

Real, recurring, expensive outages — all preventable, all the same root cause (someone forgot a date):

- **Microsoft Teams (Feb 2020)** — an expired auth/TLS certificate took Teams down globally for hours.
- **O2 / Ericsson (Dec 2018)** — an expired certificate in Ericsson software knocked out data service for ~32 million O2 users in the UK (and millions more worldwide).
- **Cloud/CDN providers** repeatedly — expired *intermediate* certs causing chain-build failures that broke thousands of healthy leaf certs at once.
- **LetsEncrypt DST Root X3 expiry (Sep 2021)** — an expiring root broke older devices that hadn't updated trust stores, demonstrating the trust-store-propagation lead-time problem in (4)/(8).

The lesson is identical every time: **monitor the whole chain, automate renewal, and treat expiry dates as production-critical data.**

---

## PRACTICE

We'll build a real expiry-scanning script: it checks local cert files and live hosts, uses `-checkend` for pass/fail, and prints a sortable report.

```bash
# ── Quick one-liners you must know cold ─────────────────────────────────

# Expiry date of a local cert
openssl x509 -in server.cert.pem -noout -enddate
# notAfter=Sep 15 12:00:00 2026 GMT

# Boolean: will it expire within 30 days? (exit 0 = still valid, 1 = expiring)
openssl x509 -in server.cert.pem -noout -checkend $((30*86400)) \
  && echo "OK >30d" || echo "EXPIRES WITHIN 30 DAYS"

# Expiry of a LIVE host (note SNI with -servername!)
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -enddate

# Inspect the FULL chain a host serves (catch the intermediate!)
echo | openssl s_client -connect example.com:443 -servername example.com -showcerts 2>/dev/null \
  | openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -noout
```

```bash
#!/usr/bin/env bash
# cert-expiry-report.sh — scan local cert files AND remote hosts for expiry.
# Usage:
#   ./cert-expiry-report.sh --dir /etc/ssl/certs --host vpn.corp.example:443 --warn 30
set -euo pipefail

WARN_DAYS=30
DIRS=(); HOSTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)  DIRS+=("$2"); shift 2 ;;
    --host) HOSTS+=("$2"); shift 2 ;;
    --warn) WARN_DAYS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
WARN_SECS=$(( WARN_DAYS * 86400 ))

printf "%-45s %-14s %-28s %s\n" "SUBJECT/SOURCE" "STATUS" "NOT_AFTER" "DAYS_LEFT"
printf '%.0s-' {1..100}; echo

# --- helper: given a PEM on stdin, evaluate and print one report row -----
evaluate_cert() {
  local source="$1" pem="$2"
  local enddate days_left status epoch_end epoch_now
  enddate=$(printf '%s' "$pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2) || {
    printf "%-45s %-14s %-28s %s\n" "$source" "UNREADABLE" "-" "-"; return; }
  # cross-platform epoch parse (GNU date vs BSD/mac date)
  epoch_end=$(date -d "$enddate" +%s 2>/dev/null || date -j -f "%b %e %T %Y %Z" "$enddate" +%s)
  epoch_now=$(date +%s)
  days_left=$(( (epoch_end - epoch_now) / 86400 ))
  if   (( epoch_end <= epoch_now ));              then status="EXPIRED"
  elif printf '%s' "$pem" | openssl x509 -noout -checkend "$WARN_SECS" >/dev/null 2>&1
       then status="OK"
  else status="EXPIRING<${WARN_DAYS}d"
  fi
  printf "%-45s %-14s %-28s %s\n" "${source:0:44}" "$status" "$enddate" "$days_left"
}

# --- scan local cert files (*.pem *.crt *.cer) --------------------------
for d in "${DIRS[@]:-}"; do
  [[ -z "$d" ]] && continue
  find "$d" -type f \( -name '*.pem' -o -name '*.crt' -o -name '*.cer' \) 2>/dev/null |
  while read -r f; do
    evaluate_cert "file:$f" "$(openssl x509 -in "$f" 2>/dev/null || true)"
  done
done

# --- scan live hosts (host:port) — check leaf AND chain -----------------
for h in "${HOSTS[@]:-}"; do
  [[ -z "$h" ]] && continue
  host="${h%%:*}"; port="${h##*:}"; [[ "$port" == "$h" ]] && port=443
  pem=$(echo | openssl s_client -connect "$h" -servername "$host" 2>/dev/null \
        | openssl x509 2>/dev/null || true)
  if [[ -z "$pem" ]]; then
    printf "%-45s %-14s %-28s %s\n" "host:$h" "UNREACHABLE" "-" "-"
  else
    evaluate_cert "host:$h (leaf)" "$pem"
  fi
done
```

```bash
# ── Run it ──────────────────────────────────────────────────────────────
chmod +x cert-expiry-report.sh
./cert-expiry-report.sh --dir ./ca-lab --host badssl.com:443 --warn 30

# Try the deliberately-expired test endpoint to see EXPIRED status:
./cert-expiry-report.sh --host expired.badssl.com:443 --warn 30

# Wire it into cron / a CLM dashboard (daily 8am), exit non-zero if anything bad:
# 0 8 * * *  /opt/pki/cert-expiry-report.sh --dir /etc/ssl --warn 30 | tee /var/log/cert-report.log
```

**Exercises:**
1. Extend the script with a non-zero exit code (and an email/Slack hook) when *any* cert is `EXPIRED` or `EXPIRING`, so it works as a Nagios/cron alert.
2. Make it parse `-showcerts` and evaluate **every cert in the chain** (leaf + intermediate), proving you'd have caught an expired-intermediate outage.
3. Add a `--warn-tiers 30,14,7,3` mode that classifies into multiple severity buckets (matches real tiered alerting from THEORY §7).
4. Add a "renewal-overdue" check: given an expected renewal window of ⅔ lifetime, flag certs that are *past* their renewal point but not yet renewed — the early-warning signal from §7.
5. Point it at your `ca-lab` from Day 08, then re-issue `server.cert.pem` with `-days 5` and watch the status flip to `EXPIRING<30d`.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. After a Heartbleed-class key exposure, an admin says "I renewed all the certs, we're fine." Are they?**
No — almost certainly not. "Renewal" that *reuses the same keypair* changes nothing about an exposed private key. They needed to **rekey** (generate fresh keypairs and issue new certs) **and revoke** the old certs. Reusing the key carries the exposure straight into the "new" cert. This is the textbook reason rekey ≠ renewal matters.

**Q2. All the leaf certs are individually valid, yet the whole site is down with chain errors. What happened?**
The **intermediate CA cert expired** (or was missing/misconfigured in the served chain). Relying parties build the path leaf → intermediate → root; if the intermediate is expired, path validation fails for *every* leaf under it simultaneously, regardless of each leaf's own validity. Monitor the whole chain, not just leaves.

**Q3. Why is the industry forcing TLS validity down toward 47 days when it's operationally painful?**
Because revocation is unreliable — CRLs go stale and OCSP soft-fails — so a short lifetime acts as *implicit revocation*: a compromised cert self-expires in weeks instead of years. It also limits the value of a stolen key and forces stale/abandoned names off fast. The pain is the point: it makes manual management impossible and forces everyone onto ACME/SCEP/EST automation.

**Q4. A user complains "Wi-Fi just stopped working" with no error. Their TLS browsing is fine. PKI angle?**
Their **EAP-TLS client certificate expired** (or was revoked). 802.1X auth fails silently — no user-facing popup — so the device just stops authenticating to the network while ordinary TLS (which uses different certs) keeps working. Check the client cert's `notAfter` and the device's auto-renewal/CLM state. This is exactly what SecureW2 auto-renewal exists to prevent.

**Q5. Why renew at ⅔ of lifetime with overlap instead of right at expiry?**
The overlap window is your **retry-and-alert budget**. Renewal can fail (network, IdP, ACME challenge), and if you renew *at* expiry a single failure is an immediate outage. Renewing early means the old cert is still valid while you retry or get paged, and the new cert overlaps so there's never a gap. Also stagger across the fleet to avoid a correlated mass-expiry.

**Q6. Renewal, rekey, reissue — define each in one line.**
Renewal = new validity, **same key**. Rekey = new validity, **new key** (real key rotation). Reissue/replace = produce a corrected/replacement cert (fix a wrong SAN/EKU or respond to an incident), usually paired with revoking the old one. Best practice: rekey on every renewal so keys rotate automatically.

**Q7. Why does rotating a root CA take a year or more, while rotating a leaf takes seconds?**
Because trust for a root lives in **every relying party's trust store** (OS, browser, device, RADIUS config), and getting a new root distributed and trusted depends on slow OS/browser update cycles — often 12–18 months — usually bridged with **cross-signing** and parallel hierarchies. A leaf, by contrast, chains to an already-trusted issuer, so replacing it is instant and fully automatable. Plan root rotation years before expiry (cf. the LetsEncrypt DST Root X3 expiry breaking un-updated devices).

**Q8. Your monitoring only alerts on expiry. Why is alerting on "renewal didn't happen" strictly better?**
Because in an automated world, a cert that *should* have auto-renewed at day 60 but hasn't by day 70 is a problem you can catch ~weeks before it expires — far earlier than an expiry alert. Expiry alerts fire when you're already near the cliff; renewal-overdue alerts fire when there's still a comfortable runway to fix the automation. The healthy signal is "renewal succeeded on schedule," and its absence is the leading indicator.

**Q9. How can a code-signing cert expire yet old signed binaries still validate?**
Through **timestamping**. If the signature was timestamped by a trusted TSA at signing time, validators check that the cert was valid *at the time of signing* rather than "now," so the signature survives the cert's expiry. Without a timestamp, signature validity is tied to current cert validity and breaks at expiry. (New signings still require a valid cert.)

---

➡ Next: [Day 10 — Revocation: CRL & OCSP](day-10-revocation-crl-ocsp.md)
