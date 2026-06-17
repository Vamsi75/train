# Day 23 — Real-Time Production Issues: Playbook

Theory wins interviews; troubleshooting wins on-call. This is the day you stop being someone who *knows* PKI and become someone people page at 2 a.m. because the whole campus can't get on Wi-Fi. Every scenario below is structured the way you should think under pressure: **symptoms → likely causes → diagnose → fix**, plus how to read the tools that tell you the truth (FreeRADIUS `-X`, `eapol_test`, Wireshark, supplicant logs). Keep this open during the incident.

---

## THEORY

### 1. The Universal Triage Decision Tree

Before diving into any specific tool, locate the failure on the path. Auth/TLS failures almost always live in one of five buckets. Walk them in order:

```
Auth/connection failing?
│
├─ 1. NAMES & REACHABILITY
│     Right hostname/SSID? DNS resolves? RADIUS reachable (UDP 1812/1813 or RadSec 2083)?
│        └─ no → fix connectivity / config (shared secret, NAS entry) first
│
├─ 2. TIME
│     Clocks in sync (client, server, CA)? Skew > a few min breaks notBefore/notAfter & TLS.
│        └─ skew → fix NTP. (Single most common "weird" cause.)
│
├─ 3. CHAIN & TRUST
│     Does each side trust the other's issuer? Full chain present? Correct root anchored?
│        └─ "untrusted"/"unknown CA" → fix chain / trust store
│
├─ 4. CERT VALIDITY & PURPOSE
│     Expired? Not-yet-valid? Revoked? Right EKU (serverAuth/clientAuth)? Name matches?
│        └─ fix the offending cert / EKU / revocation reachability
│
└─ 5. TRANSPORT / SIZE
      MTU/fragmentation of big EAP-TLS certs? Message-Authenticator? Packet loss?
         └─ tune MTU / framed-MTU / move to RadSec
```

If you internalize only one thing: **most "certificate" outages are actually #2 (time), #3 (chain), or #4 (expiry).** Most "RADIUS is broken" pages are #1 (shared secret / NAS entry) or #5 (fragmentation).

### 2. Why Expiry, Time, Chain, and EKU Are the Big Four

- **Expiry** is deterministic and silent until the second it isn't. The cert was fine yesterday; today `notAfter` passed and *everything* using it hard-fails simultaneously. Intermediates expiring are the nastiest because one expired intermediate breaks **every leaf under it** at once.
- **Clock skew** makes a perfectly valid cert look "not yet valid" or "expired," and breaks TLS nonce/handshake timing. New VMs, devices off the network for months, and dead CMOS batteries are classic sources.
- **Chain** problems are asymmetric: the *server* must send leaf + all intermediates (in order); the *client* must anchor the correct root. A server that omits the intermediate works on machines that happen to cache it and fails on fresh ones — a maddening "works on my laptop" bug.
- **EKU** (Extended Key Usage) is the purpose tag. A server cert needs `serverAuth` (`1.3.6.1.5.5.7.3.1`); a client/EAP-TLS cert needs `clientAuth` (`1.3.6.1.5.5.7.3.2`). Wrong/missing EKU = "the cert is valid but not allowed for this." Microsoft NPS additionally wants specific EKUs and (for the RADIUS server cert) the right SAN.

### 3. The EAP-TLS / RADIUS Fragmentation Problem (Know This Cold)

EAP-TLS sends the **full certificate chain** during the handshake. Those certs are large; RADIUS rides on **UDP** (1812/1813). When the EAP payload exceeds the link/path MTU it must be fragmented — at the IP layer *and* across multiple RADIUS Access-Challenge/Access-Request round-trips (EAP fragmentation). Failure modes:

- A network device drops IP fragments or has a smaller path MTU → large EAP-TLS frames silently vanish → auth hangs/times out for *some* users (those with bigger chains) but not others.
- `Framed-MTU` misconfigured on the NAS or RADIUS → fragments sized wrong.
- This gets **much worse with PQC certs** (Day 22) — kilobyte-sized signatures blow up chain size.

Mitigations: keep chains short, set sane `Framed-MTU` (commonly ~1344), fix path MTU / allow fragments, and ideally move to **RadSec (RADIUS over TLS, TCP/2083)** which handles large payloads cleanly and encrypts the whole exchange.

### 4. Shared Secret & Message-Authenticator — the Silent Failures

RADIUS authentication between NAS and server uses a **shared secret**. If it's wrong:

- The server typically **silently discards** the packet (you see *nothing* in normal logs) or logs "Received packet from X with invalid Message-Authenticator." From the client's view, RADIUS simply **never responds** — looks like a timeout/connectivity issue, not an auth issue. This is why "no response from RADIUS" so often means "wrong shared secret" or "NAS not in clients.conf."
- **Message-Authenticator** (RFC 2869, the `EAP-Message`/integrity attribute) protects packet integrity. Post the 2024 **BlastRADIUS** vulnerability, servers increasingly *require* it; a NAS that doesn't send it (or a mismatch) gets rejected. Modern FreeRADIUS may enforce `require_message_authenticator`.

### 5. RadSec, SNI, and Hostname Mismatch

- **RadSec** wraps RADIUS in TLS over TCP/2083. Now you have a *second* PKI dependency: the RadSec client (NAS/proxy) and server must trust each other's certs. RadSec failures = TLS failures (untrusted CA, expired cert, name mismatch, wrong cipher).
- **SNI (Server Name Indication):** TLS clients send the desired hostname in the ClientHello so a server hosting many sites returns the right cert. Wrong/missing SNI → server returns the *default* cert → **hostname mismatch** on the client.
- **Hostname mismatch:** the name the client asked for isn't in the cert's **SAN** (CN is ignored by modern clients). Even a perfectly valid, trusted cert fails if `connect host` ∉ SAN list.

---

## PRACTICE — Scenario Playbook

### Scenario A — "Certificate Expired" Outage

**Symptoms:** Sudden, simultaneous failures at a clean time boundary. Browsers show `NET::ERR_CERT_DATE_INVALID`; clients show "server certificate expired"; everything that used one cert breaks at once.

**Likely causes:**
- **Server (leaf) cert** expired → that service down.
- **Intermediate cert** expired → *every* leaf under it down (much bigger blast).
- **Client/EAP-TLS cert** expired → that user/device can't auth.
- **Root** expired → catastrophic, rare (long lifetimes), but devastating during migrations.

**Diagnose:**
```bash
# Server / live endpoint
openssl s_client -connect host:443 -servername host </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
# Whole chain dates (catch the expired INTERMEDIATE)
openssl s_client -connect host:443 -servername host -showcerts </dev/null
# A file on disk
openssl x509 -in cert.pem -noout -dates
openssl x509 -in cert.pem -noout -checkend 0    # exit 1 = already expired
```
For an EAP-TLS client cert, check the device's cert store (certlm.msc / Keychain) `notAfter`.

**Fix:** Re-issue/renew the offending cert (and re-install the **full chain** if an intermediate lapsed). **Prevent:** expiry monitoring + alerting, and **automated renewal** (ACME/SCEP/CLM). Never rely on a human remembering a date.

### Scenario B — EAP-TLS Authentication Failing

**Symptoms:** Device won't get on Wi-Fi/802.1X; Access-Reject or timeout; supplicant errors about the server cert or "no valid certificate."

**Likely causes → diagnose → fix:**

| Likely cause | Diagnose | Fix |
|---|---|---|
| Client doesn't trust RADIUS **server cert** (untrusted CA) | Supplicant log: "server certificate is not trusted"; `radiusd -X` shows TLS alert `unknown CA` from client | Push the correct **server-CA root** to the client trust store / profile |
| Client cert **expired / not-yet-valid** | `openssl x509 -in client.pem -noout -dates`; `radiusd -X` shows cert date error | Re-issue client cert; fix device clock if not-yet-valid |
| Client cert **revoked** | `radiusd -X` shows revocation check failure; check CRL/OCSP | Re-issue; or if false, fix CRL freshness/reachability |
| **Clock skew** | Compare client/server/CA time | Fix NTP everywhere |
| **Wrong/incomplete CA chain on RADIUS** server | `radiusd -X` can't build path to client cert's issuer; missing intermediate in `ca_file` | Put **full issuing chain** in RADIUS `ca_file`/`ca_path` |
| **EKU** missing/wrong | `openssl x509 -noout -text \| grep -A1 "Extended Key Usage"` — server needs `serverAuth`, client needs `clientAuth` | Re-issue from a template with correct EKU |
| RADIUS can't reach **CRL/OCSP** | `radiusd -X` revocation timeout; test from server | Open egress to CDP/AIA URLs; or use OCSP stapling/cached CRL |

**Key tool:** `radiusd -X` (below) shows the exact TLS handshake step that fails — it will literally print which side rejected what.

### Scenario C — "New Devices Can't Join Wi-Fi" (Onboarding)

**Symptoms:** Existing devices fine; brand-new/just-enrolled devices fail.

**Likely causes:**
- **SCEP enrollment failed** → device never got a client cert (challenge expired, SCEP URL/RA wrong, template denied).
- **MDM/profile not applied** → no Wi-Fi profile, no server-validation config, no client cert pushed.
- **Supplicant misconfig** → server validation not configured (or too strict), wrong CA pinned, wrong EAP method.

**Diagnose:** Check the device cert store for the issued client cert. Check MDM console for profile-install status. Check SCEP/NDES/CA logs for the enrollment request. On the device, inspect the network profile (server name to validate, trusted CA, EAP type).

**Fix:** Reissue SCEP challenge / fix SCEP RA config; re-push MDM profile; correct the supplicant profile (right CA, right server name, EAP-TLS). **Prevent:** validate the onboarding flow end-to-end as part of golden-image testing.

### Scenario D — RADIUS Issues

**D1. Wrong shared secret (silent drop / no response)**
- *Symptom:* client times out; RADIUS appears dead; normal log empty.
- *Diagnose:* `radiusd -X` prints `Received packet from <NAS> with invalid Message-Authenticator` or simply ignores an unknown client; verify the NAS IP is in `clients.conf`.
- *Fix:* match the secret on **both** NAS and server; add the NAS to `clients.conf`.

**D2. Message-Authenticator**
- *Symptom:* rejects after a security update; "Insufficient Message-Authenticator."
- *Fix:* ensure the NAS sends Message-Authenticator (RFC 2869); align `require_message_authenticator` (BlastRADIUS hardening).

**D3. MTU / fragmentation of large EAP-TLS certs (the classic)**
- *Symptom:* *some* users/devices fail (those with bigger chains); auth hangs/times out mid-handshake; works on small certs, fails on large.
- *Diagnose:* Wireshark shows EAP-TLS fragments not all arriving / retransmits; `radiusd -X` shows handshake stalling after Certificate. Test path MTU.
- *Fix:* set `Framed-MTU` (~1344) on NAS/RADIUS, fix path MTU / allow IP fragments, prune the cert chain, or move to **RadSec**.

**D4. NAS not configured**
- *Symptom:* no requests reach RADIUS at all.
- *Diagnose:* `radiusd -X` shows nothing from that NAS IP; tcpdump on 1812.
- *Fix:* add NAS to `clients.conf` with correct IP + secret; confirm NAS points at the right RADIUS IP/port.

**D5. Accounting failures**
- *Symptom:* auth works but no accounting/session data; NAS logs accounting timeouts.
- *Diagnose:* check UDP **1813**, accounting shared secret, and that the server's `acct` listener is up.
- *Fix:* open 1813; verify accounting secret and DB/log write path.

**D6. RadSec TLS failures**
- *Symptom:* TCP/2083 connection fails or drops; no auth.
- *Diagnose:* `radiusd -X` TLS errors; `openssl s_client -connect radsec-host:2083` to inspect cert/chain/name.
- *Fix:* fix RadSec cert chain/trust/name/cipher on both peers.

### Scenario E — Chain / Trust / SNI / Hostname Mismatch

**Symptoms:** "unable to get local issuer certificate," "self-signed certificate in chain," `ERR_CERT_AUTHORITY_INVALID`, or hostname/SAN mismatch errors.

**Diagnose:**
```bash
# Does the server send the full, ordered chain?
openssl s_client -connect host:443 -servername host -showcerts </dev/null
# Verify against a known root, supplying intermediates
openssl verify -CAfile root.pem -untrusted intermediate.pem leaf.pem
# Is SNI the problem? Compare default vs. SNI cert:
openssl s_client -connect host:443 </dev/null            # no SNI -> default cert
openssl s_client -connect host:443 -servername host </dev/null
# Hostname/SAN check
openssl x509 -in leaf.pem -noout -ext subjectAltName
```
**Fix:** Install the **complete intermediate chain** on the server (most common); anchor the correct root on clients; ensure the requested hostname is in the **SAN**; configure SNI correctly on multi-tenant front ends.

### F. Reading the Tools

**FreeRADIUS debug — `radiusd -X` (or `freeradius -X`)** — the single best diagnostic. Run it in foreground; it prints every packet, attribute, policy decision, and TLS handshake step.
- `Ready to process requests` → server is up.
- `Received packet from <ip> with invalid Message-Authenticator` → wrong shared secret.
- `(N) eap_tls: ... TLS_accept: ...` → watch the handshake march; it stops at the failing step.
- `unknown CA` / `certificate verify failed` → chain/trust problem.
- `Login OK` / `Access-Accept` vs `Login incorrect` / `Access-Reject` → final verdict, with the reason above it.

**`eapol_test`** (from wpa_supplicant) — simulate a full 802.1X/EAP exchange against RADIUS without touching an AP:
```bash
eapol_test -c eaptls.conf -s <shared-secret> -A <source-ip> 2>&1 | tee out.txt
# Look for: "EAP: Status notification: remote certificate verification"
#           "SUCCESS" / "FAILURE"
```
Gives you a clean, repeatable client-side reproduction — invaluable for isolating "is it the client or the network?"

**Wireshark filters:**
- `eapol` — the 802.1X handshake on the wire (EAPOL-Start, EAP Request/Response).
- `radius` — RADIUS Access-Request/Challenge/Accept/Reject; expand to see EAP fragmentation and attributes.
- `tls` — the EAP-TLS / RadSec handshake; check `tls.handshake.type` and **TLS alerts** (e.g., `unknown_ca`, `certificate_expired`).
- `eap` — raw EAP; watch fragment reassembly to spot MTU drops.

**Supplicant logs:**
- **Windows:** Event Viewer → Applications and Services Logs → Microsoft → Windows → **Wired-AutoConfig / WLAN-AutoConfig** (Operational); RADIUS side in **NPS** events (6273 Access-Reject with a Reason Code — *memorize the reason codes*).
- **macOS:** `/var/log/wifi.log`, Console.app, `eapolclient` logs; `log show --predicate 'process == "eapolclient"'`.
- **iOS:** sysdiagnose / Apple Configurator logs; profile-install status in MDM.

### Quick Triage Decision Tree (operational)

```
Page: "can't authenticate / can't get on Wi-Fi"
│
├─ Does RADIUS see the request? (radiusd -X / tcpdump 1812)
│   ├─ NO  → NAS not configured OR wrong shared secret OR network path. Fix #1.
│   └─ YES → continue
│
├─ Does the TLS handshake complete? (radiusd -X TLS_accept steps)
│   ├─ Stops at Certificate w/ "unknown CA" → chain/trust. Fix RADIUS ca_file or client trust.
│   ├─ "certificate expired / not yet valid" → expiry or clock skew. Fix cert / NTP.
│   ├─ revocation timeout → CRL/OCSP reachability. Open egress.
│   ├─ stalls after Certificate, only big certs fail → FRAGMENTATION. Framed-MTU / RadSec.
│   └─ completes → continue
│
├─ EKU correct? (serverAuth on server, clientAuth on client)  → fix template if not
│
└─ Still failing → policy/authorization (group, NPS network policy, VLAN). Check accept reason.
```

**Exercises:**
1. **Reproduce an expiry:** generate a cert with `-days 1` (or backdate with `faketime`), serve it, and watch `openssl s_client` + a browser report `notAfter` passed. Then renew and confirm recovery.
2. **Induce a wrong shared secret:** change the secret on the NAS/`eapol_test` side only, run `radiusd -X`, and capture the exact "invalid Message-Authenticator" / silent-drop behavior. Note that the *client* just sees a timeout.
3. **Read `radiusd -X` for EAP-TLS:** run a successful `eapol_test`, then break it three ways (remove the intermediate from `ca_file`; expire the client cert; skew the clock) and record the *exact* line in `-X` that changes each time.
4. **Fragmentation hunt:** capture an EAP-TLS auth in Wireshark, filter `eap`, and identify the certificate fragments. Lower `Framed-MTU` and observe the change in fragment count.
5. **Chain/SNI:** find a public site that returns a different cert with vs. without SNI (`-servername`), and one that omits its intermediate; write the one-line fix for each.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. RADIUS "isn't responding" and the client just times out. Walk me from page to root cause.**
"No response" almost never means the server is down for *everyone* — it usually means the server **silently dropped** that NAS's packets. Run `radiusd -X` and watch: if you see `Received packet from <NAS> with invalid Message-Authenticator` or you see *nothing at all* from that NAS IP, it's a **wrong shared secret** or the NAS isn't in `clients.conf`. Confirm reachability with `tcpdump`/Wireshark on UDP 1812 (packets arriving = network is fine). The client times out because RADIUS, by design, doesn't answer packets it can't authenticate — there's no "wrong secret" error sent back. Fix: align the secret on both sides and ensure the NAS entry exists.

**Q2. Only *some* users fail EAP-TLS; others on the same SSID are fine. What's your first hypothesis?**
**Fragmentation of large EAP-TLS certificates.** Users with longer certificate chains (more intermediates, larger keys) produce bigger EAP payloads that get IP-fragmented and split across more RADIUS round-trips. If a path-MTU bottleneck or a device dropping fragments sits between NAS and RADIUS, the big handshakes stall while small ones squeak through — a classic "works for some, not others" signature. Confirm in Wireshark (`eap` fragments not reassembling, retransmits) and `radiusd -X` (handshake stalls right after the Certificate message). Fix: set a sane `Framed-MTU`, fix path MTU / allow fragments, prune the chain, and consider RadSec. Bonus: this will get worse with PQC certs.

**Q3. A cert is valid, trusted, and unexpired — yet the client rejects it. Name three reasons.**
(1) **Hostname/SAN mismatch** — the name the client requested isn't in the cert's SAN (CN doesn't count anymore). (2) **Wrong EKU** — e.g., a server cert lacking `serverAuth`, or a RADIUS server cert lacking the EKU/SAN that NPS or the supplicant requires. (3) **SNI** — the client didn't send (or sent the wrong) SNI, so the server returned its *default* cert, which is valid but for a different name. Each is a "valid cert, wrong purpose/name" failure, not a trust failure.

**Q4. EAP-TLS fails with "unknown CA." Whose problem is it — and which side's CA?**
The TLS alert tells you the *direction*. If the **client** sends `unknown_ca`, the client doesn't trust the **RADIUS server's** issuing CA → push the correct server-CA root to the client/supplicant profile. If the **server** (`radiusd -X`) can't build a path to the **client cert's** issuer, the RADIUS `ca_file`/`ca_path` is **missing the issuing intermediate/root** → install the full client-issuing chain on the RADIUS server. Read `radiusd -X` and the TLS alert to know which way the rejection points — don't guess.

**Q5. Why is an expired *intermediate* scarier than an expired *leaf*, and why is it easy to miss?**
A leaf expiry takes down one service. An **intermediate** expiry takes down **every leaf chained under it simultaneously** — potentially your whole estate. It's easy to miss because (a) nobody monitors intermediates as closely as leafs, (b) the leaf itself looks perfectly valid (`notAfter` is far away), so naive checks pass, and (c) some clients cache the intermediate and keep working, so it "works on my machine" while fresh clients fail. Always check the **whole chain's** dates (`s_client -showcerts`), not just the leaf, and monitor intermediates explicitly.

**Q6. RADIUS auth succeeds but you have no session/usage data. Where do you look?**
That's an **accounting** failure, separate from authentication. Accounting rides UDP **1813** with its own (often same, sometimes different) shared secret. Check: is the NAS configured to send accounting to 1813? Is the server's accounting listener up? Does the accounting secret match? Can the server write to its accounting store (DB/log)? `radiusd -X` will show Accounting-Request packets arriving (or not) and any write errors. Auth and accounting are independent pipelines — one working says nothing about the other.

**Q7. A device that's been in a drawer for six months can't join the network even though its cert "isn't expired." Why?**
Two prime suspects, both time-related. (1) **Clock skew** — a dead CMOS battery or a long-powered-off device boots with a wrong clock, so the RADIUS server's *current* time falls outside what the device thinks is valid, or TLS handshake timing fails; the cert is fine, the device's *clock* is lying. Fix NTP / set time. (2) The **CRL/OCSP** the device or RADIUS relies on may be unreachable or the device's cached trust info is stale. Start by comparing the device clock to real time — it's the cheapest check and the most common culprit for "valid cert, still fails."

**Q8. How do you isolate "client misconfig" from "network/RADIUS problem" without touching an AP?**
Use **`eapol_test`**. It performs a full EAP/802.1X exchange directly against the RADIUS server using a config file and the shared secret — no AP, no RF, no supplicant GUI in the way. If `eapol_test` gets `SUCCESS`, your RADIUS/cert/chain path is good and the problem is the real client's supplicant profile or the wireless path. If `eapol_test` `FAILURE`s, run it alongside `radiusd -X` and the failing line tells you exactly which step (trust, expiry, EKU, revocation) is broken. It's the cleanest way to cut the problem in half on the first move.

➡ Next: [Day 24 — Twisted Interview Questions](day-24-twisted-interview-questions.md)
