# Day 21 — Authorization, Dynamic VLAN, NAC & Segmentation

> Day 20 ended at the magic word **Access-Accept**. But "you may enter" is only half the answer. Authentication asked *"who are you?"* — authorization asks *"now what are you allowed to do, and where do we put you?"* Today we turn an authenticated identity into a concrete **VLAN, role, and ACL**, and we wire in **NAC, segmentation, zero-trust, and CoA**.

---

## THEORY

### 1. Authentication vs Authorization (don't conflate them)

| | Authentication (AuthN) | Authorization (AuthZ) |
|---|---|---|
| Question | Who are you? | What can you do / where do you go? |
| Mechanism | EAP-TLS cert validation, IdP lookup | RADIUS reply attributes returned to the NAS |
| Output | Pass/fail identity | VLAN, role, ACL, session timeout |
| Day | 18–20 | **21 (today)** |

A RADIUS **Access-Accept** can — and usually should — carry **authorization attributes**. An Accept with no attributes just dumps the user on the port's default/native VLAN. The interesting work is the **attributes you attach**.

> **Gotcha:** AuthN success ≠ full access. A valid employee cert might still land you on a *restricted* VLAN if your device fails posture or you're a contractor. Always design the **deny/limited** path, not just the happy path.

### 2. Where the policy decision is made

The decision happens at the **RADIUS server / policy engine** (FreeRADIUS `post-auth`, NPS network policies, or a cloud policy engine). Inputs available to the decision:

- **Certificate attributes** — issuing CA, SAN/UPN, OU, custom policy OIDs, validity.
- **IdP / directory group** — read **live** (Dynamic Cloud RADIUS, Day 20) or from cached enrollment data.
- **Device posture / health** — managed vs unmanaged, AV/patch/disk-encryption state (from MDM/NAC agent).
- **Context** — SSID, NAS-Identifier, time of day, location.

Output = a set of **RADIUS attributes** in the Access-Accept.

### 3. Returning authorization: the core RADIUS attributes

**Dynamic VLAN assignment** (RFC 3580 / 2868 — the standard trio, memorize these):

```text
Tunnel-Type            = VLAN          (13)
Tunnel-Medium-Type     = IEEE-802      (6)
Tunnel-Private-Group-Id = "10"         (the VLAN ID or name)
```

All three must be present and (typically) share the same **Tag** value; the NAS places the authenticated session onto VLAN 10.

**Filter-Id** (RFC 2865, attr 11) — names a **pre-defined ACL** already configured on the switch/controller:
```text
Filter-Id = "EMPLOYEE_ACL"
```

**Downloadable ACL (dACL)** — Cisco pushes the *actual* ACL content from RADIUS (no pre-config on the switch). Cisco VSAs, e.g. `cisco-av-pair = "ip:inacl#10=permit ip any any"` or referencing an `ACS:CiscoSecure-Defined-ACL`.

**Vendor role VSAs** (return a *role* and let the controller map it):
```text
Aironet/Airespace-ACL-Name / Airespace-Interface-Name   (Cisco WLC)
Aruba-User-Role = "employee"                              (Aruba VSA 1)
```

**Session control:**
```text
Session-Timeout = 3600     # force reauth after 1h
Termination-Action = 1     # RADIUS-Request: reauthenticate, don't disconnect
Acct-Interim-Interval      # periodic accounting updates
```

> **Gotcha — VLAN by ID vs name:** Some platforms expect a numeric VLAN ID in `Tunnel-Private-Group-Id`, others accept a VLAN *name*. Mismatch = silent fallback to native VLAN. Always verify against the NAS.

> **Gotcha — tags:** the three tunnel attributes are *tagged* attributes. If tags don't match across the three, some NAS implementations ignore the assignment.

### 4. NAC (Network Access Control) concepts

NAC = controlling network admission based on **identity + device posture**, usually built on **802.1X**:

- **802.1X-based NAC** — the supplicant authenticates; the authenticator (switch/AP) gates the port; the authentication server (RADIUS) decides.
- **Posture / health checks** — is the device patched, encrypted, running AV, MDM-enrolled, jailbroken? Feeds the authz decision.
  - **Agent-based** — a NAC/MDM agent reports posture (richer, requires install).
  - **Agentless** — fingerprinting, MDM API lookup, profiling (DHCP/HTTP/MAC OUI) — no install, less detail.
- **MAB (MAC Authentication Bypass)** — for devices with no supplicant (IoT/printers): switch sends MAC as the identity; RADIUS allows from an allowlist and **segments hard**.
- **Profiling** — classify device type to drive the policy (e.g. "this is a printer" → IoT VLAN).

### 5. Guest access & captive portals

- **Open/PSK SSID → captive portal** (web-auth): user accepts AUP or logs in via sponsor/social/SMS.
- RADIUS can still authorize guests onto a **guest VLAN** (e.g. 50) with **internet-only ACL**, isolated from corporate.
- **Onboarding bridge:** a captive portal can also redirect to **JoinNow self-service** (Day 20) to *upgrade* a guest into a certificate-enrolled user.

### 6. Device segmentation (the whole point)

Map populations to isolated segments so a compromise is contained:

| Population | VLAN | Access |
|---|---|---|
| Employee (managed, healthy) | 10 | Full corporate |
| BYOD / personal | 30 | Internet + limited apps |
| Contractor | 20 | Scoped apps only |
| IoT / printers | 40 | Locked ACL, no lateral, no internet-out except updates |
| Guest | 50 | Internet-only, isolated |

**Microsegmentation** pushes this further — segment **within** a VLAN (host-to-host policy, SGTs/TrustSec, host firewalls) so even same-VLAN devices can't freely talk.

### 7. Zero Trust Network Access (ZTNA) principles

- **Never trust, always verify** — every session re-evaluated; identity + device posture each time.
- **Least privilege** — authorize the *minimum* (role/ACL), not "full LAN."
- **Assume breach** — segment so lateral movement is hard; the network edge is not a trust boundary.
- 802.1X + dynamic authz + microsegmentation is the **on-prem network expression** of zero trust. The cert says who; the live IdP/posture check says "still allowed, on *these* resources, *right now*."

### 8. CoA — Change of Authorization (RFC 5176)

RADIUS can **change or kill a session mid-flight** without waiting for reauth:

- **CoA-Request** — push new attributes (e.g. move VLAN, apply quarantine ACL) to the NAS for an active session.
- **Disconnect-Message (DM)** — terminate the session (force reconnect).
- Sent on **UDP/3799** from the RADIUS/policy server to the NAS.

**Use cases:** a NAC posture check fails after connect → CoA to a remediation VLAN; security disables a user in the IdP → DM to kick them; a device finishes onboarding → CoA to move from provisioning VLAN to production. CoA is what makes authorization **continuous**, not one-shot at connect.

> **Gotcha:** CoA must be enabled on the NAS, with a shared secret and the correct source allowed. Many "why didn't quarantine work?" tickets are just CoA not configured on the switch/controller.

---

## PRACTICE

### A. FreeRADIUS `post-auth`: assign VLAN by group

After EAP-TLS succeeds, an LDAP/IdP lookup populates a group attribute (here `LDAP-Group` / an internal `User-Group`). In `sites-enabled/default`, the `post-auth { }` section:

```text
post-auth {
    # Look up group already retrieved in authorize (ldap / rest module)
    # Then map group -> VLAN using an if/else policy:

    if (&LDAP-Group == "Employees-FullTime") {
        update reply {
            &Tunnel-Type := "VLAN"
            &Tunnel-Medium-Type := "IEEE-802"
            &Tunnel-Private-Group-Id := "10"
            &Filter-Id := "EMPLOYEE_ACL"
            &Session-Timeout := 3600
            &Termination-Action := RADIUS-Request
        }
    }
    elsif (&LDAP-Group == "Contractors") {
        update reply {
            &Tunnel-Type := "VLAN"
            &Tunnel-Medium-Type := "IEEE-802"
            &Tunnel-Private-Group-Id := "20"
            &Filter-Id := "CONTRACTOR_ACL"
        }
    }
    elsif (&TLS-Client-Cert-Issuer =~ /BYOD/) {
        update reply {
            &Tunnel-Type := "VLAN"
            &Tunnel-Medium-Type := "IEEE-802"
            &Tunnel-Private-Group-Id := "30"
            &Filter-Id := "INTERNET_ONLY"
        }
    }
    else {
        # default: deny or drop onto a restricted holding VLAN
        update reply {
            &Tunnel-Type := "VLAN"
            &Tunnel-Medium-Type := "IEEE-802"
            &Tunnel-Private-Group-Id := "99"   # quarantine
        }
    }
}
```

> Tip: `Tunnel-*` are tagged attributes — in FreeRADIUS you may write `&Tunnel-Type:0 := VLAN` etc. to set tag 0 explicitly when a NAS is picky.

### B. Aruba role instead of raw VLAN

```text
update reply {
    &Aruba-User-Role := "employee"     # controller maps role -> VLAN+ACL+QoS
}
```

### C. Sample policy table (group → VLAN → ACL → role)

```text
| Identity source                | Posture     | VLAN | ACL / Filter-Id   | Role        |
|--------------------------------|-------------|------|-------------------|-------------|
| AD: Employees-FullTime         | healthy     | 10   | EMPLOYEE_ACL      | employee    |
| AD: Employees-FullTime         | non-compliant| 99  | QUARANTINE_ACL    | remediate   |
| AD: Contractors                | any         | 20   | CONTRACTOR_ACL    | contractor  |
| Cert issued by BYOD CA         | any         | 30   | INTERNET_ONLY     | byod        |
| Cert issued by IoT CA / MAB    | any         | 40   | IOT_LOCKDOWN      | iot         |
| No cert (captive portal)       | n/a         | 50   | GUEST_ACL         | guest       |
```

### D. CoA example (move a quarantined device after remediation)

Using `radclient` to send a CoA-Request to the NAS (UDP/3799):

```bash
echo "User-Name='alice', \
NAS-IP-Address=10.0.0.5, \
Acct-Session-Id='0A0B0C0D', \
Tunnel-Type:0=VLAN, \
Tunnel-Medium-Type:0=IEEE-802, \
Tunnel-Private-Group-Id:0=10" \
| radclient -x 10.0.0.5:3799 coa testing123
```

Disconnect (kick) an active session — Disconnect-Message:

```bash
echo "User-Name='bob', NAS-IP-Address=10.0.0.5, Acct-Session-Id='AABBCCDD'" \
| radclient -x 10.0.0.5:3799 disconnect testing123
```

> The NAS replies `CoA-ACK`/`Disconnect-ACK` on success, or `CoA-NAK`/`Disconnect-NAK` (often with an `Error-Cause`) if it can't find the session or CoA isn't enabled.

**Exercises:**
1. Write the three mandatory attributes for dynamic VLAN from memory; state what happens if you omit `Tunnel-Medium-Type`.
2. Extend the `post-auth` policy: employees on a **non-compliant** device (posture flag) go to VLAN 99 with `QUARANTINE_ACL`, then a CoA moves them to VLAN 10 once they remediate. Sketch the message flow.
3. Compare `Filter-Id` vs **dACL**: when is pushing the full ACL from RADIUS better than referencing a pre-defined one? (Hint: switch config drift.)
4. A printer does MAB on VLAN 40 with `IOT_LOCKDOWN`. Write the ACL intent (no lateral, allow only print ports + vendor update host).
5. Explain how 802.1X + dynamic authz + CoA + microsegmentation together implement **zero trust** on a campus LAN. Where is the weakest link?
6. Your CoA-Request returns NAK with `Error-Cause = Session-Context-Not-Found`. Give two likely causes.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. The user authenticated successfully but landed on the wrong VLAN. Walk me through debugging.**
Confirm the Access-Accept actually carried the **three tunnel attributes** (capture with `radclient`/`radiusd -X` or NAS debug). Check: are all three present with **matching tags**? Is `Tunnel-Private-Group-Id` a VLAN **ID** when the NAS expects a **name** (or vice-versa)? Does that VLAN exist and is it trunked to the AP/switch? Is a NAS-side override (interface override, AAA override disabled on the WLC) ignoring the RADIUS value? Silent fallback to native VLAN almost always = one of those four.

**Q2. Difference between `Filter-Id` and a downloadable ACL?**
`Filter-Id` returns a **name**; the ACL itself must already be configured on the switch/controller — RADIUS just selects it. A **dACL** returns the **actual ACL contents** (Cisco av-pairs), so the switch needs no pre-configured ACL — central management, no config drift across hundreds of switches, but more RADIUS-side complexity and a Cisco-centric mechanism. Use dACL when you want ACLs managed centrally and consistently; use `Filter-Id` for simple, vendor-neutral, pre-staged ACLs.

**Q3. How can you change a user's access *without* disconnecting them?**
**CoA-Request (RFC 5176)** on UDP/3799: the RADIUS/policy server pushes new authorization (new VLAN, quarantine ACL, role) to the NAS for the live session. The NAS re-applies authz, often forcing a brief re-auth, but you don't have to wait for the next 802.1X cycle. If you *do* want to drop them, send a **Disconnect-Message**. CoA is the mechanism behind "posture failed → quarantine now" and "user disabled in IdP → kick."

**Q4. Authorization based on a certificate attribute vs a live IdP group — when do you use which?**
Cert-attribute authz (issuing CA, OU, policy OID, SAN) is **fast and offline** — great for coarse segmentation (BYOD CA → VLAN 30) and works even if the directory is down. Live IdP-group authz is **current** — it reflects HR changes, group moves, and disables in real time (Day 20's Dynamic Cloud RADIUS). Best practice: use cert attributes for **structural/segment** decisions and the live IdP lookup for **dynamic/entitlement** decisions, with a sane fallback if the IdP is unreachable.

**Q5. A device passes 802.1X but is unpatched and full of malware. How does this architecture limit damage?**
Multiple layers: **posture/NAC** can detect non-compliance and authorize it to a **quarantine/remediation VLAN** instead of corporate. Even on its assigned segment, **dynamic ACLs** and **microsegmentation/SGTs** restrict what it can reach (no lateral movement, least privilege). **CoA** can re-quarantine it the moment posture flips. Zero-trust assumption: authentication does not equal trust — segment and monitor regardless.

**Q6. Why is dynamic VLAN assignment better than statically mapping SSID→VLAN or port→VLAN?**
Static mapping means one SSID/port = one segment for everyone, forcing multiple SSIDs (broadcast overhead, management) and ignoring identity. Dynamic VLAN lets a **single Enterprise SSID** sort users into employee/BYOD/contractor/IoT VLANs **by identity and posture**, follows the user as roles change (an AD group move + reauth/CoA relocates them), and scales cleanly. Fewer SSIDs, identity-driven segmentation.

**Q7. What's the relationship between `Session-Timeout`, `Termination-Action`, and reauth?**
`Session-Timeout` tells the NAS how long the session is valid. `Termination-Action` controls what happens at expiry: value **1 (RADIUS-Request)** means **reauthenticate** (re-run 802.1X, re-evaluate authz — including a fresh IdP/posture check) without fully tearing down; default **0 (Default)** means terminate the session. For zero-trust you want periodic reauth so authorization is re-validated — pair a reasonable `Session-Timeout` with `Termination-Action = RADIUS-Request`, or drive re-evaluation via CoA.

**Q8. Guest who later becomes an employee — how does the network handle the transition cleanly?**
Guest hits the **captive portal** on the guest VLAN (50, internet-only). The portal redirects them to **JoinNow self-service onboarding**, where they auth to the IdP, get a **certificate**, and receive the Enterprise SSID profile. On next connect they do **EAP-TLS**, the policy engine reads their employee group, and dynamic VLAN places them on VLAN 10. Optionally a **CoA** moves them immediately. One identity lifecycle, no manual VLAN surgery.

**Q9. CoA isn't working in your lab — what do you check?**
(1) **Enabled on the NAS** — dynamic-authorization/CoA client configured with the policy server's IP and **shared secret**. (2) **Port 3799/UDP** reachable (firewall/source-IP allowlist). (3) Correct **session identifiers** — `Acct-Session-Id` / `User-Name` / `NAS-IP-Address` must match the live session, else `Session-Context-Not-Found` NAK. (4) Vendor quirks — some NAS need the originating server IP to exactly match a configured CoA client. Capture the CoA-NAK's `Error-Cause` — it usually tells you which of these failed.

---

➡ Next: [Day 22 — Security Threats, Crypto-Agility & PQC](day-22-security-threats-crypto-agility-pqc.md)
