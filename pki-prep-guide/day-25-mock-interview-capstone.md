# Day 25 — Mock Interview & Design Capstone

This is the day you stop studying and start *performing*. Below is a simulated panel interview, three open-ended design scenarios with worked solutions, a whiteboard architecture you should be able to draw from memory, and a brutally honest self-assessment checklist. Read the answers, then close the file and reproduce them out loud.

---

## Part A — Simulated Panel Interview

*Setting: a panel of three — a PKI architect, a network/AAA lead, and a security engineer. Questions get progressively harder. Model answers are written the way a strong senior candidate would actually speak.*

**Q1 (warm-up, conceptual). "Walk me through what happens, end to end, when a corporate laptop joins the secure Wi-Fi."**

> The laptop's 802.1X supplicant associates to the AP and the AP, acting as authenticator, blocks all traffic except EAP. The supplicant and the RADIUS server negotiate EAP-TLS. The RADIUS server presents its server certificate; the supplicant validates it against the trusted CA *and* checks the server name — that's what stops a rogue RADIUS server. The supplicant then presents its client certificate and signs the handshake transcript with its private key, proving possession. The RADIUS server builds and validates the chain to our trusted CA, checks revocation, and maps the cert identity (UPN in the SAN) to a user/group. On success it returns Access-Accept with authorization attributes — Tunnel-Type=VLAN, Tunnel-Medium-Type=802, Tunnel-Private-Group-ID=<VLAN>. The AP moves the port to that VLAN and opens it. No password ever crossed the air.

**Q2 (conceptual, sharper). "You said the supplicant validates the server name. Why isn't validating the CA enough?"**

> Because the CA can have issued certs to many servers — possibly a public CA that issued to anyone. If I only pin the CA, an attacker holding any cert chaining to that CA can impersonate my RADIUS server and, with a tunneled method, harvest inner credentials. So I pin both the trusted root *and* the expected RADIUS server name/SAN. With EAP-TLS there's no inner secret to steal, but I still validate the name to avoid rogue-server games and to keep the policy tight.

**Q3 (mechanism). "In EAP-TLS, exactly where does the client prove it owns the key — not just possesses a copy of the cert?"**

> In the CertificateVerify message. The cert itself is public — anyone could replay it. The client signs a hash of the entire live handshake transcript with its private key; the server verifies that signature with the public key in the cert. Since the transcript includes fresh, unpredictable data, a replay can't produce a valid signature. Mutual auth is only complete after both the server's and the client's transcript signatures verify.

**Q4 (scenario). "A user authenticated fine yesterday. Today, every AP rejects them. Where do you look?"**

> One user across all APs points at the credential, not the infrastructure — if it were the infrastructure I'd expect many users failing on one NAS. I'd pull the RADIUS reject reason: most likely the client cert expired, was revoked, failed chain/trust validation, or there's clock skew making a valid cert look not-yet-valid or expired. I'd check `notAfter`, the device clock/NTP, and the CRL/OCSP status. If the reject reason is identity-mapping, maybe their UPN/group changed. I localize by cross-tabbing failures by NAS and by user before touching anything.

**Q5 (scenario, deeper). "The reject reason says 'unable to get certificate CRL.' What does that tell you and what do you do?"**

> The RADIUS server is configured to enforce revocation but can't reach the CRL Distribution Point or OCSP responder from its network segment — so it's failing closed, which is actually the *correct* security posture. The fix is connectivity, not disabling the check: verify the CDP/AIA URLs in the cert are reachable from the RADIUS server, that the CRL isn't stale/expired, and that any proxy/firewall allows the fetch. I would not "fix" it by turning off revocation checking — that re-introduces the exact gap we built revocation to close.

**Q6 (design). "We're a 5,000-person company on PEAP-MSCHAPv2 and we keep getting phished. Pitch me the move to EAP-TLS in two minutes."**

> PEAP-MSCHAPv2 carries a password-derived exchange that, with weak server-cert validation, an evil-twin RADIUS server harvests and cracks offline. EAP-TLS removes the password entirely — auth is a client certificate and a private key that never leaves the device, ideally TPM-bound and non-exportable. There's nothing to phish. We onboard users once via an IdP-authenticated portal (Okta/Entra) that issues a per-device cert, then daily network access is passwordless and doesn't even depend on the IdP being up. We run both methods in parallel on separate SSIDs or via policy during migration, move device cohorts over, and decommission PEAP only after the population is fully enrolled. Net: phishing-resistant auth, fewer helpdesk password resets, and horizontal RADIUS scaling because cert validation is stateless.

**Q7 (design trade-off). "Where's the catch in EAP-TLS? Sell me the downside too."**

> Three real costs. One, lifecycle: you now run a CA and must automate issuance, renewal, and revocation — a cert that silently expires is an outage, so renewal automation is non-negotiable. Two, onboarding friction for BYOD/unmanaged devices — you need a smooth self-service flow (SCEP/EST via MDM or a portal). Three, the un-credentialable tail — IoT and legacy gear can't hold a cert, so you need MAB/iPSK and segmentation alongside. EAP-TLS is the right answer, but it's a *program*, not a setting.

**Q8 (architecture). "Our single RADIUS server is a SPOF for all network access. Fix it without splitting trust."**

> Run at least two RADIUS servers active/active with identical trust config and CA trust store, and put primary+secondary on every NAS. Because cert validation is stateless — each server validates each cert independently against the same trust anchors and revocation source — there's no session state to replicate. Front cloud RADIUS with RadSec and load-balancing, and keep policy in a shared store. For survivability, local RadSec proxies with cached CRLs so a WAN blip to cloud RADIUS doesn't black out the building. Trust stays unified; only availability scales out.

**Q9 (incident). "Mid-quarter, a developer's laptop is stolen with an 11-month cert. What now?"**

> Revoke the cert and confirm the RADIUS servers actually *enforce* and refresh revocation — issuing a revocation that nobody checks is theater. De-provision the device in MDM/IdP so even a non-enforcing path drops it. Use CoA to disconnect any live sessions. Rekey onto a replacement device — never reuse the key. Then the post-mortem: was the key extractable? If it wasn't TPM-bound and non-exportable, that's the real finding, and I'd push the key-storage policy. Bonus: this is an argument for shorter cert lifetimes so the revocation window matters less.

**Q10 (forward-looking, hardest). "Your CA root is good for 20 years. Quantum is the elephant. What do you do today?"**

> The root's signature algorithm is the long-lived exposure — RSA/ECC signatures fall to Shor's, and a 20-year root outlives the likely threat horizon, so it's exactly the thing to make crypto-agile first. I'd plan for hybrid signatures (classical + ML-DSA/SLH-DSA) and ensure my issuance pipeline and HSMs can support PQC algorithms, because agility is architectural — dual-algorithm issuance, automated re-issuance, and a deployed-cert inventory — not a flag. For confidentiality I'd prioritize PQC key exchange (ML-KEM, hybrid) on long-lived sensitive flows now because of harvest-now-decrypt-later. Symmetric/hash layers just need AES-256 and SHA-384+. The honest answer is I don't rip out a working root today; I make sure I *can* migrate it on a year's notice, which most orgs with manual PKI cannot.

---

## Part B — Design Scenarios (Worked Solutions)

### Scenario 1 — Passwordless Wi-Fi for a 10,000-employee company with BYOD + IoT

**Requirements.** 10k employees, managed laptops + personal phones (BYOD), plus printers/cameras/sensors (IoT). Phishing-resistant, scalable, segmented.

**Solution.**

| Population | Auth method | Onboarding | Network placement |
|---|---|---|---|
| Managed laptops/desktops | EAP-TLS (TPM-bound cert) | MDM pushes cert via SCEP/EST | Corp VLAN, full access by group |
| BYOD phones/tablets | EAP-TLS (per-device cert) | Self-service portal: IdP login (Entra/Okta) → issue cert via SCEP/EST | BYOD VLAN, restricted ACLs |
| IoT / printers / cameras | MAB or iPSK (per-device PSK) | MAC inventory / PSK provisioning | Isolated IoT VLAN, no lateral access, tight egress ACL |

- **PKI:** offline root → purpose-specific issuing CAs (user, device). ECC P-256 leaf keys to keep EAP-TLS payloads small and avoid 802.1X fragmentation pain. Short-ish lifetimes (e.g., 1 year users, shorter for BYOD) with fully automated renewal.
- **AAA:** redundant cloud or on-prem RADIUS, RadSec from controllers, active/active, identical trust store. Authorization by IdP/AD group → dynamic VLAN via Tunnel-Private-Group-ID.
- **Onboarding:** IdP authenticates the human once; the portal issues a cert; the password is never used for network auth again — phishing-resistant by construction.
- **IoT:** never forced into EAP-TLS. Segmented so an un-authenticatable device can't degrade the secure population. NAC posture + CoA to quarantine misbehaving devices.
- **Revocation:** enforced on RADIUS (CRL with delta + cached, or OCSP stapling), tied to HR/IdP de-provisioning so leavers actually lose access.

**Why it scales:** cert validation is stateless, so RADIUS scales horizontally; IdP is only in the path at enrollment, not every association.

### Scenario 2 — Hospital certs expired and knocked everyone off Wi-Fi at 2 AM. Diagnose & prevent.

**What happened (diagnosis).** A synchronized mass outage at a clock boundary screams *expiry* or *time*. Most likely the issuing CA certificate (or a widely-deployed intermediate) hit `notAfter`, or a large cohort of device certs issued in the same batch expired together — both produce "everyone fails at once." A close runner-up is the RADIUS *server* certificate expiring: every EAP-TLS supplicant validating the server cert rejects it simultaneously, so *all* clients drop even though their own certs are fine. The 2 AM timing aligns with a midnight/UTC `notAfter`.

**Immediate triage.**
1. Read a reject reason: client-cert expired vs server-cert untrusted/expired vs CRL-fetch failure vs clock skew.
2. If it's the RADIUS server cert or an intermediate — reissue/renew it immediately and push; supplicants recover on reassociation.
3. If it's a batch of client certs — emergency renewal/reissue, and as a bridge, a temporary fallback SSID for critical clinical devices (carefully scoped).
4. Verify NTP — a time fault can masquerade as expiry.

**Prevention (the real deliverable).**
- **Automate renewal** so certs are never manually tracked. Renew at, say, 2/3 of lifetime, not at the cliff.
- **Stagger issuance** so a cohort never all expires on the same day (jitter the validity windows).
- **Monitor and alert on `notAfter`** for *every* cert in the chain — root, intermediates, RADIUS server certs, and a sample of leaf certs — with alerts weeks ahead, paging at thresholds.
- **Watch the infrastructure certs specifically** — the RADIUS server cert and intermediates are single points of mass failure and are the ones humans forget.
- **NTP as a monitored, redundant service.**
- **Runbook + ownership:** a named owner for PKI expiry, dashboards, and a tested renewal procedure. The root cause here is almost always "no one owned expiry monitoring," not a crypto failure.

### Scenario 3 — Migrate PEAP-MSCHAPv2 → EAP-TLS with zero downtime

**Goal.** Move the whole org off password-based PEAP to cert-based EAP-TLS without a flag day and without locking anyone out.

**Phased plan.**

1. **Stand up PKI + onboarding in parallel.** Issuing CA for device/user certs, IdP-authenticated onboarding portal, MDM SCEP/EST profiles. No change to existing Wi-Fi yet.
2. **Configure RADIUS to accept *both* methods.** Same SSID can negotiate either EAP-TLS or PEAP, or run a parallel SSID for the cert-based method. RADIUS policy: if a valid client cert is presented → EAP-TLS path; else fall back to PEAP. This is the key to zero downtime — both work simultaneously.
3. **Enroll in cohorts.** Push certs to managed devices via MDM (silent). Drive BYOD through the self-service portal. Track enrollment coverage in the device inventory.
4. **Prefer EAP-TLS once enrolled.** Enrolled devices automatically use the cert method; un-enrolled ones keep using PEAP, so nobody is locked out mid-migration.
5. **Monitor and chase the tail.** Dashboard PEAP vs EAP-TLS auth ratios per cohort. The long tail is unmanaged/legacy devices — address with targeted onboarding or move them to MAB/iPSK + segmentation.
6. **Tighten then disable PEAP.** Once a cohort is fully enrolled, remove PEAP for that group (by SSID or policy). Finally retire PEAP entirely.

**Guardrails.** Server-cert validation must be enforced on supplicants throughout (even PEAP). Use ECC certs to avoid fragmentation surprises. Keep a documented rollback (re-enable PEAP per group) until the last cohort is cut over. Never disable PEAP globally before enrollment hits ~100% for that population.

---

## Part C — Whiteboard Architecture (draw this from memory)

End-to-end: device onboarding → EAP-TLS auth → dynamic VLAN.

```
            ┌─────────────────────────── ONBOARDING (one-time) ───────────────────────────┐
            │                                                                              │
   ┌────────┴─────────┐     IdP login (SAML/OIDC)     ┌──────────────┐                     │
   │  Device / User   │ ───────────────────────────▶ │     IdP      │  proves human ID    │
   │  (supplicant)    │                               │ (Entra/Okta) │                     │
   └────────┬─────────┘ ◀── cert issued (SCEP/EST) ── └──────┬───────┘                     │
            │                                                │ authorize enrollment        │
            │                                        ┌───────▼────────┐   ┌──────────────┐ │
            │                                        │ Onboarding /   │──▶│ Issuing CA   │ │
            │                                        │  MDM gateway   │   │ (online)     │ │
            │   private key stays in TPM (non-       └────────────────┘   └──────┬───────┘ │
            │   exportable); cert installed                                      │ signed  │
            └────────────────────────────────────────────────────────────  by   ▼         │
                                                                          ┌──────────────┐ │
                                                                          │ Offline ROOT │ │
                                                                          │     CA       │ │
                                                                          └──────────────┘ │
            └──────────────────────────────────────────────────────────────────────────────┘

            ┌────────────────────────── DAILY NETWORK ACCESS (EAP-TLS) ─────────────────────┐
            │                                                                                │
 ┌──────────┴───────┐   802.1X / EAP     ┌──────────────┐   RADIUS/RadSec   ┌──────────────┐│
 │  Device          │ ◀───────────────▶ │ AP / Switch  │ ◀──────────────▶  │ RADIUS (AAA) ││
 │  (client cert +  │   EAPOL frames     │ (Authenticator/│  (EAP tunneled  │  server(s)   ││
 │   private key)   │                    │     NAS)     │   in RADIUS)      │ active/active││
 └──────────────────┘                    └──────┬───────┘                   └──────┬───────┘│
        │  1. assoc; port blocked except EAP            ▲                          │        │
        │  2. server cert → client validates CA+name    │                          │        │
        │  3. client cert + CertificateVerify (proof)   │                  validates chain, ││
        │  4. RADIUS validates chain + revocation       │                  revocation (CRL/ ││
        │  5. Access-Accept + VLAN tunnel attrs ────────┘                  OCSP), maps UPN  ││
        │                                                                          │        │
        │              ┌───────────── revocation source ──────────┐               │        │
        │              │  CRL Distribution Point / OCSP responder  │◀──────────────┘        │
        │              └───────────────────────────────────────────┘                        │
        ▼                                                                                    │
   ┌─────────────────────────────────────────────────────────────────┐                      │
   │ Access-Accept attributes drive authorization:                    │                      │
   │   Tunnel-Type = VLAN (13)                                         │                      │
   │   Tunnel-Medium-Type = 802 (6)                                    │                      │
   │   Tunnel-Private-Group-ID = <VLAN id/name>   → switch sets VLAN   │                      │
   │   (+ ACL / session-timeout / posture)        CoA can re-VLAN later│                      │
   └─────────────────────────────────────────────────────────────────┘                      │
            └────────────────────────────────────────────────────────────────────────────────┘
```

**Talking points while you draw:** root is offline and only signs the issuing CA; the IdP is in the path *only at onboarding*; the private key never leaves the TPM; the AP is a dumb relay that never sees inside the TLS tunnel; trust + revocation decisions live on the RADIUS server; authorization is delivered as the three tunnel attributes; CoA lets NAC re-VLAN mid-session.

---

## Part D — Final Self-Assessment Checklist

Can you, **without notes**, do each of these? Be honest — anything you can't, go back and drill before the interview.

**Crypto & X.509**
- [ ] Explain whose keys sign vs are signed in a cert, and why the subject's private key is never in it.
- [ ] Explain why we hash before signing, and the difference between encryption and signing.
- [ ] Explain why ECDSA P-256 ≈ RSA-3072 and why smaller certs matter for 802.1X.
- [ ] Read a cert and name where the relying identity (SAN UPN/email) comes from.

**PKI & trust**
- [ ] Justify the offline root and why low usage enables it.
- [ ] Explain intermediates for containment, and cross-signing for migration.
- [ ] Explain what the CA copies from a CSR and what it ignores — and why CSR SANs aren't trusted.

**Lifecycle & revocation**
- [ ] Distinguish renewal from rekey and say when each is mandatory.
- [ ] Explain why OCSP soft-fail breaks revocation and how stapling/Must-Staple fix it.
- [ ] Give three reasons a revoked cert still authenticates.
- [ ] Argue short-lived certs as an alternative to revocation — and its single failure mode.

**TLS / mTLS / EAP**
- [ ] Pinpoint where confidentiality and identity happen in a TLS 1.2 vs 1.3 handshake.
- [ ] Explain exactly where mutual auth completes in EAP-TLS (both CertificateVerify steps).
- [ ] Explain why EAP-TLS is phishing-resistant and PEAP-MSCHAPv2 isn't.
- [ ] Explain why a client cert alone doesn't prove ownership (CertificateVerify).
- [ ] Explain what TEAP/EAP-chaining adds over PEAP/TTLS.

**RADIUS & 802.1X**
- [ ] Explain what the RADIUS shared secret protects and what it leaves in the clear.
- [ ] Name the three VLAN tunnel attributes and why one missing attribute fails silently.
- [ ] Explain why a large client cert chain breaks 802.1X and four ways to fix it.
- [ ] Explain CoA, its port/secret, and the firewall/NAT failure mode.
- [ ] Explain why cert validation being stateless lets RADIUS scale horizontally.

**Design & incident**
- [ ] Design passwordless Wi-Fi for managed + BYOD + IoT, with segmentation.
- [ ] Diagnose a mass expiry/clock outage and build the prevention program.
- [ ] Plan a zero-downtime PEAP→EAP-TLS migration with dual-method fallback.
- [ ] Run a stolen-key incident: revoke, enforce, de-provision, rekey, hunt key storage.
- [ ] Explain crypto-agility as architecture, PQC migration shape, and harvest-now-decrypt-later.
- [ ] Draw the full onboarding → EAP-TLS → dynamic VLAN architecture from memory.

If you can check every box and speak the whiteboard diagram aloud while drawing it, you are interview-ready. Go get it.

---

➡ Back to [README](README.md)
