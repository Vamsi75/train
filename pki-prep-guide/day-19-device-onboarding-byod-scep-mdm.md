# Day 19 — Device Onboarding & BYOD

> "PKI without onboarding is a vault with no front door. The hard part of EAP-TLS was never the math — it's getting a *trusted* client cert and a *correct* Wi-Fi profile onto ten thousand heterogeneous devices, and ripping them back out on offboarding." — every network engineer who's done a Wi-Fi migration.

Day 18 got the *identity* into shape. Today we get the **certificate and the supplicant configuration onto the device** — managed and BYOD, across Windows / macOS / iOS / Android / ChromeOS — without users hand-editing Wi-Fi settings and disabling the very protections that make EAP-TLS safe. This is the operational core of SecureW2's JoinNow story.

---

## THEORY

### 1. The onboarding problem, stated precisely

To put a device on a passwordless EAP-TLS network you must deliver **four things** to it, correctly, every time:

1. A **private key** generated *on the device* (it must never leave — that's the whole security model).
2. A **client certificate** binding the IdP identity (Day 18) to that key.
3. The **trusted CA certificate(s)** the device uses to validate the RADIUS server.
4. A **Wi-Fi/network profile** that says: SSID, **EAP-TLS**, which client cert to present, **which CA to trust**, and **the exact RADIUS server name to verify**.

Miss any one and you either can't connect *or* — worse — you connect insecurely. Doing this by hand across five OS families, each with its own profile format and UI, is where breaches and helpdesk tickets are born. Onboarding automates all four.

### 2. Managed vs BYOD vs unmanaged

| Class | Who controls it | Enrollment path | Cert key store |
|---|---|---|---|
| **Managed (corporate)** | Org, via **MDM** (Intune, Jamf, Workspace ONE, Google Admin) | MDM **pushes** a profile + SCEP payload silently | OS keychain / TPM, often non-exportable |
| **BYOD (personal)** | User owns it; org has limited reach | **Self-service** portal: user authenticates, an app/agent enrolls | OS keystore, user-scoped |
| **Unmanaged / guest** | Nobody trusted | Usually **not** given a cert — PSK guest VLAN or captive portal | n/a |

Key tension: managed devices you can *force*; BYOD you must *invite* (the user must consent, authenticate, and install). Both should land on the **same EAP-TLS network** with a per-device cert — the difference is purely *how the cert gets there*.

### 3. Path A — MDM-driven onboarding (managed devices)

The MDM is already the device's source of truth. Use it as the delivery vehicle.

```text
1. Device is enrolled in MDM (Intune/Jamf/WS1/Google).
2. Admin configures a SCEP (or PKCS) certificate profile
   + a Wi-Fi profile (EAP-TLS) in the MDM console.
3. MDM pushes both to the device silently (no user action).
4. Device generates a keypair, builds a CSR, and enrolls via
   SCEP through the MDM/SCEP proxy to the CA.
5. CA issues the cert; MDM installs it + the Wi-Fi profile.
6. Device connects with EAP-TLS. Done — zero touch.
```

- **SCEP** (Simple Certificate Enrollment Protocol): device gets a one-time **challenge password**, sends a CSR, receives a cert. The protocol every major MDM speaks for cert enrollment.
- **PKCS profile** (Intune term): the cert/key is generated **server-side** and delivered as a PKCS#12 — used when the device can't do SCEP keygen well, or for shared scenarios. SCEP (on-device key) is preferred for non-exportability.
- **EST** (Enrollment over Secure Transport): the modern, TLS-based successor to SCEP — mutual-TLS, cleaner crypto. Increasingly supported.

### 4. Path B — Self-service onboarding (BYOD, the JoinNow pattern)

No MDM on the device, so the *user* drives a guided flow:

```text
1. User connects to onboarding SSID / hits the portal URL.
2. Portal redirects to the IdP (Day 18: SAML/OIDC) — user
   authenticates with MFA. Identity + groups returned.
3. Portal hands the user a small native app / dissolvable agent
   (JoinNow-style) OR a downloadable config profile.
4. The agent GENERATES A KEYPAIR locally (key never leaves device),
   builds a CSR, and enrolls via SCEP/EST to the CA — carrying the
   IdP identity that policy maps into the SAN.
5. Agent installs: the client cert, the trusted CA cert, and a
   Wi-Fi profile (EAP-TLS, correct server name, correct CA).
6. Agent configures the SUPPLICANT and connects. It then
   "dissolves" (no permanent software left behind).
```

A **dissolvable agent** runs once and removes itself — important for BYOD where users won't tolerate permanent corporate software. On iOS/macOS the same outcome is achieved with a `.mobileconfig` configuration profile (no app needed); on Windows a small client or a generated profile; on Android via an app or Android Enterprise; on ChromeOS via Google Admin policy.

### 5. Configuration profiles by platform

The "Wi-Fi profile" is concrete, OS-specific config. Know the artifact for each:

| OS | Artifact | Notes |
|---|---|---|
| **iOS / iPadOS / macOS** | `.mobileconfig` (signed XML plist) | Carries CertificatePayload + SCEP payload + Wi-Fi (EAPClientConfiguration) payload in one signed bundle. |
| **Windows** | Wireless profile XML + cert in cert store; pushed via MDM CSP, GPO, or onboarding client | EAP-TLS config in `EapHostConfig` / OneX XML. |
| **Android (Enterprise)** | Managed config / **Android Enterprise** Wi-Fi policy, or app-applied | `WifiEnterpriseConfig` (EAP-TLS, CA cert, client cert alias, **domain/altSubjectMatch** for server validation). |
| **wpa_supplicant** (Linux/Android internals) | `wpa_supplicant.conf` network block | The lowest-level supplicant config — see Practice. |
| **ChromeOS** | Google Admin Console network + cert policy | ONC (Open Network Configuration) JSON. |

### 6. The MDM Gateway / SCEP proxy pattern

A raw SCEP challenge is a weak shared secret. If anyone with a CSR + challenge could get a cert, your CA is an open issuer. The fix is a **SCEP proxy / MDM gateway** that sits between the device and the CA and **validates the request against the MDM before issuing**:

```text
Device --SCEP--> [SCEP Proxy / MDM Gateway] --validate--> MDM (is this
                         |                                  device enrolled,
                         |                                  compliant, owned by
                         |                                  the claimed user?)
                         v
                    CA issues cert  <-- only if MDM says YES
```

- The gateway checks the **device is genuinely enrolled and compliant in the MDM**, and that the CSR's identity matches what the MDM knows — before forwarding to the CA.
- This binds the cert to a **real, validated device**, not just to whoever replayed a challenge. SecureW2's gateway model does exactly this for Intune/Jamf/WS1.
- It also lets you inject the correct **SAN attributes** (from MDM/IdP) into the issued cert rather than trusting the device's self-asserted CSR subject.

### 7. The manual-config security hole — server validation

This is the single most important security point of the day. EAP-TLS (and PEAP) require the **client** to validate the **RADIUS server's** certificate. If it doesn't, an attacker stands up a rogue AP + rogue RADIUS and the client happily authenticates to it — credential theft (PEAP) or downgrade attacks.

When users configure Wi-Fi **by hand**, they:
- Skip / disable "Validate server certificate."
- Don't pin the **CA** that signed the RADIUS cert.
- Don't set the **expected server name** (so *any* cert from *any* CA the device trusts is accepted).

```text
Manual config (BAD):                  Onboarded profile (GOOD):
  [ ] Validate server certificate       Trusted CA: <your private RADIUS CA>
  Trusted CA: (none / public)           Server name: radius.corp.com (pinned)
  Server name: (blank/any)              EAP: EAP-TLS, client cert from SCEP
                                        Server validation: enforced, cannot disable
```

**Onboarding exists largely to make the secure choice the only choice** — the profile hard-codes the correct CA and server name and the user can't toggle them off. Never let users hand-configure 802.1X.

### 8. Lifecycle — revoke on offboarding / MDM unenroll

Issuing the cert is half the job; **getting it back** is the other half. Tie certificate lifecycle to device/identity lifecycle:

- **MDM unenroll / wipe** → trigger **revocation** of that device's cert (the gateway knows the device↔cert mapping).
- **User offboarded** (SCIM `active:false`, Day 18) → revoke all of that user's certs.
- **Lost/stolen device** → revoke immediately; publish to CRL/OCSP so RADIUS rejects it on next connect.
- **Cert expiry / renewal** → MDM or the onboarding client auto-renews before expiry (silent for managed; re-prompt for BYOD).

Remember from Day 18: because EAP-TLS doesn't consult the IdP at auth time, **revocation is the only off-switch** — disabling the account does nothing to a cert already on the device.

---

## PRACTICE

### A. iOS `.mobileconfig` — EAP-TLS + SCEP payload outline

A `.mobileconfig` is a (usually signed) plist with an array of payloads. Below are the *key fields* of the three payloads that matter: SCEP (get a cert), and Wi-Fi (use it with EAP-TLS). Real files are larger; these are the load-bearing keys.

```xml
<!-- ===== SCEP payload: enroll for a client cert ===== -->
<dict>
  <key>PayloadType</key>            <string>com.apple.security.scep</string>
  <key>PayloadIdentifier</key>      <string>com.corp.scep</string>
  <key>PayloadUUID</key>            <string>UUID-SCEP-...</string>
  <key>PayloadContent</key>
  <dict>
    <key>URL</key>      <string>https://scep.corp.com/scep</string>  <!-- SCEP/gateway endpoint -->
    <key>Name</key>     <string>CorpClientCert</string>
    <key>Challenge</key><string>ONE-TIME-CHALLENGE</string>           <!-- validated by gateway -->
    <key>Subject</key>  <array><array><array><string>CN</string>
                          <string>$EMAIL</string></array></array></array>
    <key>SubjectAltName</key>
       <dict><key>rfc822Name</key><string>$EMAIL</string></dict>      <!-- IdP identity in SAN -->
    <key>Keysize</key>  <integer>2048</integer>
    <key>Key Type</key> <string>RSA</string>
    <key>KeyUsage</key> <integer>5</integer>                          <!-- digital sig + key enc -->
  </dict>
</dict>

<!-- ===== Wi-Fi payload: EAP-TLS using that cert ===== -->
<dict>
  <key>PayloadType</key>   <string>com.apple.wifi.managed</string>
  <key>SSID_STR</key>      <string>CORP-SECURE</string>
  <key>EncryptionType</key><string>WPA2</string>          <!-- WPA2/WPA3-Enterprise -->
  <key>EAPClientConfiguration</key>
  <dict>
    <key>AcceptEAPTypes</key>        <array><integer>13</integer></array>  <!-- 13 = EAP-TLS -->
    <key>TLSTrustedServerNames</key> <array><string>radius.corp.com</string></array> <!-- server name pin -->
    <key>PayloadCertificateAnchorUUID</key>
        <array><string>UUID-OF-TRUSTED-CA-PAYLOAD</string></array>        <!-- pin the CA -->
  </dict>
  <key>PayloadCertificateUUID</key> <string>UUID-SCEP-...</string>        <!-- present SCEP cert -->
</dict>
```

The critical fields, and *why*:
- **`AcceptEAPTypes = 13`** — forces EAP-TLS (cert), not PEAP.
- **`TLSTrustedServerNames`** — pins the RADIUS server name; defeats rogue-RADIUS attacks.
- **`PayloadCertificateAnchorUUID`** — pins *your* CA as the only acceptable anchor for the server cert.
- **SCEP `SubjectAltName / rfc822Name = $EMAIL`** — bakes the IdP identity into the SAN (Day 18 binding).
- The whole `.mobileconfig` should be **signed** so iOS shows it as "Verified" and the user can't silently tamper.

### B. Intune SCEP profile — fields to set

```text
Certificate type:        User  (or Device)
Subject name format:     CN={{UserPrincipalName}}
Subject alternative name:
    - URI / UPN:         {{UserPrincipalName}}        # SAN UPN
    - Email:             {{EmailAddress}}             # SAN rfc822Name
Key storage provider:    TPM (preferred) / Software
Key usage:               Digital Signature, Key Encipherment
Key size:                2048
Extended key usage:      Client Authentication (1.3.6.1.5.5.7.3.2)
Validity period:         1 year (match your policy)
SCEP Server URL(s):      https://gateway.corp.com/scep   # the SCEP proxy/gateway
Root CA certificate:     <linked trusted CA profile>     # pushed separately first
Renewal threshold (%):   20   # auto-renew at 20% remaining lifetime
```
Pair it with a **Trusted Certificate** profile (pushes the CA) and a **Wi-Fi** profile (EAP-TLS, references the SCEP cert + trusted CA, sets the server name). Intune `{{...}}` tokens are populated from Entra ID — that's the Day 18 identity flowing into the SAN.

### C. wpa_supplicant EAP-TLS block (the lowest level)

```text
network={
    ssid="CORP-SECURE"
    key_mgmt=WPA-EAP
    eap=TLS
    identity="alice@corp.com"
    ca_cert="/etc/wpa/corp-ca.pem"        # pin the CA (server validation)
    client_cert="/etc/wpa/alice.pem"       # the enrolled client cert
    private_key="/etc/wpa/alice.key"
    private_key_passwd="..."               # or use a TPM/PKCS#11 token
    domain_suffix_match="radius.corp.com"  # SERVER NAME CHECK — do not omit
}
```
`domain_suffix_match` (or `altsubject_match`) is the wpa_supplicant equivalent of iOS `TLSTrustedServerNames`. Omitting it is the classic "no server validation" hole.

### D. Supplicant configuration checklist (every platform, every time)

```text
[ ] EAP method = EAP-TLS (not PEAP/MSCHAPv2)
[ ] Client certificate present, key non-exportable (TPM/secure enclave where possible)
[ ] Client cert SAN carries the correct IdP identity (UPN / email)
[ ] Trusted CA = YOUR private RADIUS CA only (not "any trusted CA", not public roots)
[ ] Server name validation ENABLED and pinned to the exact RADIUS FQDN
[ ] User CANNOT disable server validation (profile-enforced, locked)
[ ] WPA2/WPA3-Enterprise (AES), not WPA2-PSK
[ ] Auto-join configured; old PSK/PEAP profiles removed to prevent fallback
[ ] Renewal configured before expiry; revocation hooked to offboarding/unenroll
```

**Exercises:**
1. Build a minimal iOS `.mobileconfig` skeleton with the three payloads above (SCEP, Trusted CA, Wi-Fi). Identify which UUIDs must cross-reference each other.
2. In an Intune SCEP profile, explain what breaks if you set Subject name to `CN={{UserPrincipalName}}` but forget the SAN — and why RADIUS policy may then fail.
3. Take the wpa_supplicant block and deliberately remove `domain_suffix_match`. Describe the exact attack this enables and the steps the attacker takes.
4. Diagram the SCEP-proxy/MDM-gateway flow and mark the single point where a non-enrolled device gets rejected.
5. Write the offboarding runbook: user leaves → which systems fire, in what order, ending with the device being rejected at RADIUS. Include both managed and BYOD cases.
6. Compare SCEP (on-device key) vs PKCS#12 (server-side key) delivery: list one security advantage and one operational scenario for each.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why generate the private key *on the device* instead of issuing a PKCS#12 from the server?**
On-device key generation means the private key **never traverses the network and never exists anywhere else** — ideally it's sealed in a TPM/secure enclave and is non-exportable. A PKCS#12 was generated server-side and shipped to the device, so it existed off-device, could be intercepted in transit, and can often be copied to another machine — that breaks the "one cert = one device identity" assumption. SCEP/EST do on-device keygen; PKCS#12 is a fallback for devices that can't, or for shared scenarios. Default to on-device keys.

**Q2. A user disabled "Validate server certificate" when setting up Wi-Fi by hand. What's the actual exploit?**
Without server validation the supplicant will authenticate to **any** RADIUS server, including a rogue one. An attacker stands up a rogue AP broadcasting your SSID plus a rogue RADIUS server. With PEAP-MSCHAPv2 the client sends its MSCHAPv2 challenge/response into the attacker's tunnel → offline credential cracking. Even with EAP-TLS, lack of server name pinning enables downgrade/relay tricks. The defense is exactly what onboarding enforces: pin the **CA** and the **server name**, and lock the toggle so the user can't disable it. This is *the* reason manual 802.1X config is banned in serious deployments.

**Q3. What does the SCEP proxy / MDM gateway actually add — isn't the SCEP challenge enough?**
A SCEP challenge is a shared secret; if it leaks or is reused, anyone can submit a CSR and get a valid cert — your CA becomes an open issuer. The gateway adds **authorization**: before forwarding the CSR to the CA, it checks with the MDM that *this specific device is genuinely enrolled, compliant, and owned by the claimed user*, and it can rewrite the SAN with trusted attributes rather than trusting the device's self-asserted subject. So the gateway turns "anyone with a challenge" into "only a validated, known device." That's the difference between a cert that proves *device identity* and a cert that proves *possession of a secret*.

**Q4. Managed and BYOD both end up on the same EAP-TLS SSID. So what's the real difference?**
Only the **delivery mechanism** and **trust level of the key store** differ. Managed devices get the SCEP + Wi-Fi profile **pushed silently by MDM** with keys often in a hardware-backed, non-exportable store and zero user interaction. BYOD requires the **user to authenticate to the IdP and run a self-service/dissolvable flow** that enrolls and configures the supplicant, with a user-scoped key store and consent. Same destination network, same EAP-TLS, same per-device cert — different on-ramp. You can also apply different policy (validity period, allowed VLAN) based on managed vs BYOD.

**Q5. A laptop is wiped/unenrolled from MDM but the ex-employee kept a copy of the machine. Is your network safe?**
Only if you **revoked the certificate**. EAP-TLS doesn't call the IdP or MDM at auth time, so an unenroll or account disable alone leaves a perfectly valid cert that still authenticates. The MDM-unenroll (or SCIM offboarding) event **must trigger revocation** of that device's cert, published to CRL/OCSP, so RADIUS rejects it on the next connect. If the key was TPM-sealed and non-exportable, a wipe also destroys it — but you should never rely on that alone. Revocation is the authoritative off-switch.

**Q6. Why does the onboarding flow install a trusted CA cert, and what exactly should it trust?**
The device must validate the **RADIUS server's** certificate during the EAP-TLS handshake. It does that against a trust anchor — and that anchor must be **your private RADIUS-issuing CA only**, not the public root store. If you trusted any publicly-trusted CA, an attacker could present a server cert from some other public CA and pass validation. So onboarding installs your specific CA as the anchor *and* pins the expected server FQDN. Trusting "any valid CA" is a common and serious misconfiguration.

**Q7. What's the difference between SCEP, EST, and a PKCS profile, and when would you pick each?**
**SCEP** — legacy-but-ubiquitous enrollment: device generates the key, sends a CSR with a challenge, gets a cert; supported by every MDM. **EST** — the modern TLS/mutual-TLS successor with cleaner crypto and stronger client auth; pick it where supported. **PKCS profile (Intune)** — server generates the key/cert and delivers a PKCS#12; use only when the device can't do on-device keygen or you need a specific shared/recoverable key, accepting the weaker key-handling. Default: SCEP/EST (on-device key) for client auth; PKCS#12 as the exception.

**Q8. On iOS, which `.mobileconfig` keys are non-negotiable for a secure EAP-TLS profile, and why?**
`AcceptEAPTypes = 13` (forces EAP-TLS), `TLSTrustedServerNames` (pins the RADIUS server name), `PayloadCertificateAnchorUUID` (pins your CA as the only acceptable server-cert anchor), and the SCEP payload's `SubjectAltName` carrying the IdP identity (the cert↔identity binding). Plus the profile should be **signed** so iOS marks it Verified and the user can't tamper. Drop the server-name or anchor keys and you've recreated the manual "no server validation" hole inside an automated profile — which is worse, because now it looks trustworthy.

**Q9. Walk the full offboarding chain for a BYOD phone with a self-enrolled cert.**
HR offboards → IdP marks the user inactive → **SCIM** propagates `active:false` (Day 18) → the certificate-management/onboarding system looks up that user's issued certs (it recorded the user↔cert↔device mapping at enrollment) → **revokes** them and updates CRL/OCSP → the next time the phone tries EAP-TLS, RADIUS checks revocation status, sees "revoked," and returns Access-Reject. Because it's BYOD there's no MDM wipe, so revocation is doing *all* the work — disabling the IdP account would have left the phone connecting fine. This is the practitioner's favorite gotcha.

---

➡ Next: [Day 20 — SecureW2 Platform Architecture](day-20-securew2-platform-architecture.md)
