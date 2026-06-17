# Day 20 — SecureW2 Platform Architecture (Passwordless Network Security)

> Everything from Days 1–19 — X.509, CA hierarchies, CSR/SCEP/EST, CRL/OCSP, EAP-TLS, RADIUS — was the *vocabulary*. Today we assemble the *sentence*: a modern, cloud-delivered, passwordless network-access platform. SecureW2 is the archetype, but the architecture generalizes (Cloudpath/RUCKUS, Portnox, Microsoft Intune+NPS, etc.). I'll flag clearly what is **conceptual/architectural** vs **vendor-specific naming**.

---

## THEORY

### 1. The problem this platform exists to solve

Passwords on the network are the root of most breaches: phishing, credential stuffing, shared PSKs, password reuse. The Wi-Fi/wired enterprise wants:

- **No passwords on the wire** → use **EAP-TLS** (certificate-based, mutual auth). Nothing phishable transmitted.
- **No on-prem CA to run** → managed cloud PKI.
- **No NPS/IAS farm to patch** → RADIUS-as-a-service.
- **Identity stays in the IdP** (Entra ID, Okta, Google) → the network should *honor* IdP state in real time.
- **Self-service enrollment** for any OS and BYOD → no helpdesk tickets.

The platform is essentially the **glue** between four worlds that historically didn't talk: the **IdP** (who you are), the **PKI** (proof you can carry), the **RADIUS/AAA** layer (the bouncer at the door), and the **network fabric** (APs, controllers, switches that enforce VLAN/role).

> **Gotcha:** People call this "passwordless," but the *enrollment* step usually still uses the password/MFA **once** (against the IdP) to bootstrap trust. After that, the certificate is the credential. The password never touches Wi-Fi again.

### 2. Managed / Cloud PKI (turnkey CA hierarchy)

Conceptually identical to Day 8–10 hierarchy design, but delivered as a service:

- A **two-tier hierarchy** is provisioned for you: an offline-style **Root CA** and one or more **Issuing/Intermediate CAs**, with private keys held in the provider's HSMs (FIPS 140-2/3).
- The platform issues **client certificates** (for users/devices — the EAP-TLS identity) and **server certificates** (for the RADIUS server's TLS identity that supplicants validate).
- You can run **separate issuing CAs per use case** (employee, BYOD, IoT, VPN) so you can revoke/segment cleanly.
- **Revocation** is published via **CRL and/or OCSP** endpoints the cloud RADIUS can consult — but see §5, the modern trick is to lean on IdP lookups instead of (or in addition to) CRL.

**Why it matters:** the hardest part of EAP-TLS at scale is *operating the CA* (key ceremonies, CRL hosting, HSM, rotation). Cloud PKI removes that operational burden while keeping the cryptographic model standard X.509.

> **Vendor-specific:** SecureW2 calls this "Managed PKI" / "Cloud PKI." The *concept* is just hosted CA-as-a-service.

### 3. Cloud RADIUS (RADIUS-as-a-service)

- **Multi-tenant, geo-distributed** RADIUS servers (each customer logically isolated). Endpoints are reachable globally so a roaming user hits a nearby PoP → low latency.
- Speaks classic **RADIUS/UDP (1812/1813)** to NAS devices, but the modern, secure transport is **RadSec (RADIUS over TLS, TCP/2083)** from your APs/controllers directly to the cloud — encrypts the RADIUS conversation across the internet and survives NAT/keepalive better than UDP.
- **High availability** is built in: multiple servers behind the same anycast/DNS name; controllers configured with primary+secondary.
- Performs the **EAP-TLS** termination: validates the client cert chains to the managed CA, checks expiry/revocation, then makes the **authorization** decision (Day 21).

> **Gotcha — server cert trust:** supplicants must be configured to trust the *RADIUS server certificate* (CN/SAN + issuing CA). If you don't pin this, you've reintroduced the evil-twin EAP attack. JoinNow's onboarding configures this trust automatically — that's a big reason self-service onboarding exists.

### 4. JoinNow onboarding (enrollment) and the Connector

**JoinNow MultiOS** = the self-service onboarding application/landing page:

1. User browses to an onboarding URL (or it's pushed).
2. Authenticates **once** to the IdP (SAML/OIDC, MFA included).
3. The client app generates a **keypair on the device**, builds a **CSR**, the cloud PKI signs it.
4. The cert + the full Wi-Fi/802.1X profile (SSID, EAP-TLS settings, **server-cert trust pinning**) are installed into the OS keystore/profile.

**JoinNow Management Portal** = admin console: define networks, policies, certificate templates, IdP connections, view logs.

**JoinNow Connector** = packaging for **MDM-driven** enrollment (Intune, Jamf, Workspace ONE, etc.). Instead of the user self-enrolling, the MDM pushes a profile that triggers **SCEP/ACME** enrollment to the cloud PKI's gateway. Good for managed/corporate devices and headless onboarding.

| Path | Who | Mechanism |
|---|---|---|
| Self-service (MultiOS) | BYOD, users | User auths to IdP → app generates CSR → cert installed |
| MDM (Connector) | Managed devices | MDM profile → SCEP/ACME → cert silently provisioned |
| Headless/IoT | Printers, IoT | Bulk/SCEP/manual cert load, often a dedicated CA |

### 5. IdP integrations & **Dynamic Cloud RADIUS** (the killer feature)

The platform integrates with identity providers via standard protocols:

- **Entra ID / Azure AD, Okta, Google Workspace** via **SAML/OIDC** (for the *enrollment* auth).
- **On-prem AD** via a **lightweight connector / LDAP** (an outbound agent so you don't expose AD to the internet).

The classic model: cert is issued, and *all* identity is baked into the cert at enrollment time. Problem: if you disable the user in the IdP, the cert still works until it expires or you revoke it (CRL latency).

**Dynamic Cloud RADIUS** fixes this. At **authentication time**, the policy engine does a **real-time lookup** back to the IdP/directory using an identifier from the cert (e.g. UPN/email in the SAN):

- **User disabled/deleted in Entra ID → RADIUS denies the connection immediately.** No revocation, no CRL wait.
- **Group membership read live** → drives VLAN/role (Day 21). Move a user to a new AD group → next reauth lands them on a new VLAN.

> This is the architectural punchline: **the certificate proves identity continuity; the IdP lookup enforces current authorization.** Auth = cert; Authz = live IdP state. That's what makes it "dynamic."

### 6. Gateways / connectors (bridging cloud ↔ on-prem)

Because most enterprises are hybrid, the platform ships lightweight on-prem **connectors** (outbound-only, no inbound firewall holes):

- **RADIUS gateway/connector** — terminate RADIUS locally or proxy on-prem AD auth.
- **LDAP connector** — secure tunnel from cloud policy engine to on-prem AD/LDAP for lookups.
- **SCEP/MDM gateway** — accepts SCEP/ACME enrollment requests (often from MDM) and relays to cloud PKI.

These keep AD/LDAP behind the firewall while still feeding the cloud brain.

### 7. End-to-end story (the one you must be able to draw)

```text
ENROLLMENT (one-time)
  User/Device ──auth(SAML/OIDC, MFA)──▶ IdP (Entra/Okta/Google)
       │ generate keypair + CSR
       ▼
  JoinNow ──CSR──▶ Cloud PKI (Issuing CA in HSM) ──signed client cert──▶ device keystore
       └─ installs 802.1X profile + RADIUS server-cert trust

CONNECTION (every time)
  Device ── WPA2/WPA3-Enterprise (SSID) ──▶ AP / WLAN Controller (NAS)
                                              │  802.1X / EAP-TLS
                                              │  RadSec (TLS/2083)
                                              ▼
                                       Cloud RADIUS (PoP)
                                        1) validate client cert → chains to managed CA?
                                        2) expiry / revocation (OCSP/CRL)?
                                        3) DYNAMIC LOOKUP → IdP/AD: user active? groups?
                                        4) policy engine → decision
                                              │
        Access-Accept + authz attrs ◀────────┘
        (Tunnel-Private-Group-Id=VLAN, Filter-Id/role, Session-Timeout)
                                              │
  AP/switch enforces ─▶ VLAN / role / ACL  (employee | byod | iot | guest)
```

> **What's conceptual vs vendor:** EAP-TLS, RADIUS, RadSec, SCEP/ACME, SAML/OIDC, X.509 — **all standards**. "JoinNow," "MultiOS," "Connector," "Dynamic Cloud RADIUS," "Management Portal" — **SecureW2 product names** for those standard roles.

### 8. Why this beats PSK / PEAP-MSCHAPv2

| Approach | Phishable? | Per-user identity? | Revoke one user? | Roaming/MITM safe? |
|---|---|---|---|---|
| WPA2-PSK | shared secret leaks | No | Rotate whole SSID | No |
| PEAP-MSCHAPv2 | Yes (creds on wire, evil-twin) | Yes | Disable in AD | Weak |
| **EAP-TLS + Cloud PKI** | **No (no secret transmitted)** | **Yes (cert)** | **Revoke cert / disable in IdP** | **Yes (mutual TLS)** |

---

## PRACTICE

### Design exercise: 5,000 employees + BYOD + IoT

You're the architect. Map the org onto the platform and draw the request flow.

**Inventory:**
- 5,000 employees, ~2 devices each (laptop + phone) → ~10,000 managed/BYOD endpoints.
- BYOD personal laptops/phones (self-service).
- ~1,500 IoT/headless devices (printers, cameras, badge readers).
- IdP: Entra ID (cloud-joined) + remaining on-prem AD.
- Network: cloud-managed APs + WLAN controllers in 6 sites; supports RadSec.

**Step 1 — PKI design**

```text
Root CA (offline, HSM)
 ├─ Issuing CA: Corp-Employees   (client certs, 1-yr, EAP-TLS)
 ├─ Issuing CA: BYOD             (client certs, 90-day, separate CRL)
 ├─ Issuing CA: IoT              (client certs, long-lived, SCEP bulk)
 └─ Issuing CA: RADIUS-Server    (server cert for cloud RADIUS)
```
Separate issuing CAs = clean revocation + clean policy boundaries.

**Step 2 — Enrollment paths**

```text
Managed laptops (Intune/Jamf)  → JoinNow Connector → SCEP/ACME → Corp-Employees CA
Employee phones (BYOD)         → JoinNow MultiOS self-service → Corp-Employees or BYOD CA
Personal/contractor devices    → MultiOS self-service → BYOD CA (90-day)
IoT/printers                   → SCEP gateway / bulk import → IoT CA
```

**Step 3 — IdP integration**
- Entra ID via **OIDC/SAML** for enrollment auth (MFA enforced).
- On-prem AD via **LDAP connector** (outbound) for residual accounts + live group lookups.
- Enable **Dynamic Cloud RADIUS** → on every auth, look up the user's status & group.

**Step 4 — RADIUS / network**
- Cloud RADIUS, **RadSec** from all 6 sites' controllers (primary + secondary PoP).
- One **WPA2/WPA3-Enterprise SSID** ("CORP") for all employee/BYOD; dynamic VLAN sorts them.
- Separate SSID or wired ports for IoT.

**Step 5 — Authorization mapping (preview of Day 21)**

| Source group / CA | Segment | VLAN | Notes |
|---|---|---|---|
| AD `Employees-FullTime` | Employee | 10 | full access |
| AD `Contractors` | BYOD/restricted | 20 | internet + limited apps |
| BYOD CA | Personal | 30 | internet-only |
| IoT CA | IoT | 40 | ACL-locked, no lateral |
| (no cert) | Guest | 50 | captive portal |

**Step 6 — draw the connection flow** (do this on a whiteboard):

```text
Phone(cert) ─WPA3-Ent▶ AP ─RadSec▶ CloudRADIUS
   ↑ validate cert→BYOD CA ✓  ↑ live lookup Entra: user active? group=Employees-FullTime
   └─ Access-Accept: Tunnel-Private-Group-Id=10, Session-Timeout=3600
AP places device on VLAN 10
```

**Exercises:**
1. The CISO disables a terminated employee in Entra ID at 14:00. With *only* CRL (24h), when do they lose Wi-Fi? With Dynamic Cloud RADIUS? Explain both.
2. Draw where a **RadSec proxy** vs a **RADIUS connector** sits, and justify which you'd deploy at a site with flaky internet.
3. A printer can't do 802.1X EAP-TLS. List two compliant ways to network it within this architecture (hint: MAB + segmentation, dedicated IoT CA/SCEP).
4. Why issue the RADIUS *server* cert from a dedicated issuing CA rather than the employee CA? (Think trust pinning + blast radius.)
5. Label every protocol in your end-to-end diagram (EAP-TLS, RadSec, OIDC, SCEP, LDAP) and mark which are standards vs product names.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. "Passwordless" — but the user typed a password during enrollment. Is it really passwordless?**
Yes, in the sense that matters: the password (and MFA) is used **once** against the IdP to bootstrap trust and issue a certificate. After that, the network credential is the **private key + cert**, which is never transmitted (EAP-TLS sends only the public cert and a signature). There is no phishable secret on the wire and no password to reuse, rotate, or steal off the AP. The attack surface of "credentials on Wi-Fi" is eliminated.

**Q2. If the cert already proves identity, why does Dynamic Cloud RADIUS still hit the IdP on every auth?**
Because a cert proves *who was enrolled*, not *whether they're still authorized right now*. A cert is valid until expiry or revocation, and CRL/OCSP propagation has latency. Real-time IdP lookup lets you **disable a user in Entra ID and have them denied at the next authentication/reauth** — and read **live group membership** to assign VLAN/role. Auth = cert (continuity); Authz = live directory state (currency).

**Q3. What's the difference between RADIUS and RadSec, and why does a cloud RADIUS service push RadSec?**
Classic RADIUS is UDP/1812 with a weak shared-secret-based obfuscation (only the password attribute is protected, MD5-based) — fine on a trusted LAN, **terrible across the internet**. RadSec wraps the entire RADIUS exchange in **TLS over TCP/2083**: full encryption, mutual cert auth between NAS and server, reliable transport, NAT/keepalive friendly. For a geo-distributed cloud service reached over the public internet, RadSec is effectively mandatory for confidentiality and integrity.

**Q4. A supplicant trusts "any cert from our CA" for the RADIUS server. What's wrong, and how does JoinNow prevent it?**
That's the **evil-twin EAP attack** enabler. If the client only checks "issued by our CA" without pinning the **server name (CN/SAN)**, an attacker who obtains *any* cert from that CA (or a misconfigured one) can stand up a rogue RADIUS and harvest credentials. Proper config pins **both** the issuing CA **and** the exact server name(s). JoinNow's onboarding installs the profile with the correct server-cert trust + name validation automatically, removing the human-misconfiguration risk — that's a core reason self-service onboarding exists, not just convenience.

**Q5. Where do you draw the line between "this is SecureW2" and "this is just a standard"?**
The cryptography and protocols are all open standards: X.509, EAP-TLS, RADIUS/RadSec, SCEP/ACME/EST, SAML/OIDC, LDAP, 802.1X, dynamic-VLAN RADIUS attributes. What SecureW2 (or any such platform) provides is **operational packaging**: hosted CA + HSM, multi-tenant geo-RADIUS, automated onboarding that configures supplicant trust correctly, a policy engine doing live IdP lookups, and outbound connectors so AD/LDAP stay behind the firewall. You're buying *running it correctly at scale*, not new crypto.

**Q6. How do you onboard a headless IoT device that can't do EAP-TLS interactively?**
Options, in order of preference: (a) **SCEP/ACME bulk provisioning** to a dedicated **IoT issuing CA** if the device supports certs (then EAP-TLS); (b) if no 802.1X at all, **MAC Authentication Bypass (MAB)** against an allowlist, placed on a **tightly segmented IoT VLAN with ACLs** so a compromised device can't move laterally; (c) for managed IoT, push a cert via the **MDM/SCEP gateway**. The architecture's answer to "can't authenticate strongly" is always "authenticate as well as possible **and segment hard**."

**Q7. The IdP is down. What happens to network access?**
Depends on configuration. With strict Dynamic Cloud RADIUS doing a mandatory live lookup, an IdP outage can block new auths — so good designs use **caching / fallback**: cache recent group/status lookups for a TTL, or fall back to cert-only validation (cert + revocation) when the IdP is unreachable, accepting a small authz-staleness window. This is a real availability/security tradeoff you must call out in design reviews; never assume the lookup is free or always up.

**Q8. Why separate issuing CAs per use case (employee/BYOD/IoT) instead of one big CA?**
Blast radius and policy clarity. Separate CAs let you **revoke an entire population** (e.g. kill all BYOD) by distrusting one CA, give each a different lifetime/policy (90-day BYOD vs 1-yr employee), and write **clean RADIUS policy keyed on issuing CA**. One monolithic CA forces you to discriminate on cert fields alone and makes a CA-key compromise catastrophic across all populations.

**Q9. What stops an employee from exporting their cert+key and using it from an unmanaged device?**
Several layers: provision keys as **non-exportable** in the OS keystore / hardware-backed (TPM, Secure Enclave) so the private key can't be extracted; tie certs to managed devices via **MDM/SCEP** so the device identity matters; and use **Dynamic Cloud RADIUS** + device posture so an unmanaged device fails policy even if it somehow presents a valid cert. Defense in depth — hardware key protection is the strongest single control.

---

➡ Next: [Day 21 — Authorization, Dynamic VLAN, NAC & Segmentation](day-21-authorization-dynamic-vlan-nac-segmentation.md)
