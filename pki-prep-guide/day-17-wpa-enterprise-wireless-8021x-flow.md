# Day 17 — WPA2/WPA3-Enterprise: The Full Wireless 802.1X Flow

> Personal Wi-Fi shares one secret with everyone. Enterprise Wi-Fi gives every user/device its own cryptographic identity, brokered by RADIUS, with keys that are unique per session. This is the difference between "the password is on a sticky note" and "this laptop has a cert that the CA can revoke in seconds." SecureW2's whole platform lives in this gap.

---

## THEORY

### 1. WPA-Personal (PSK) vs WPA-Enterprise (802.1X/EAP)

| | WPA2/3-**Personal** (PSK / SAE) | WPA2/3-**Enterprise** (802.1X/EAP) |
|---|---|---|
| Credential | One shared passphrase for the whole SSID | Per-user/per-device identity (cert or login) |
| Key source | PMK = PBKDF2(passphrase, SSID) — *everyone derives the same PMK* | PMK derived from per-session **MSK** from RADIUS |
| Auth server | None | **RADIUS** (e.g. Cloud RADIUS) |
| Revoke one user | **Rotate the PSK for everyone** | Disable the user / revoke the cert — others unaffected |
| Identity / accounting | None (all clients identical) | Username/cert in logs, VLAN/role per user |
| Attack surface | Offline crack of captured 4-way handshake; insider leak | No shared secret to leak; phishing-resistant with EAP-TLS |

**Why PSK doesn't scale — the shared-secret problem:**
- Everyone knows the same passphrase → one leak compromises the whole network, and the only remediation is **re-keying every device**.
- A captured 4-way handshake (just sniff one client associating) can be **brute-forced offline** (WPA2). Weak passphrase = game over.
- No per-user identity → no role-based VLANs, no accounting, no targeted revocation, no MFA.
- An insider who leaves keeps access until you rotate the PSK org-wide.

WPA-Enterprise fixes all of this by inserting **802.1X + RADIUS**: each session authenticates a unique identity and derives **unique keying material**, so a compromise is isolated to one identity and revocable instantly.

### 2. WPA2-Enterprise vs WPA3-Enterprise

- **WPA2-Enterprise**: 802.1X auth, **AES-CCMP** (128-bit) data encryption, PMK from MSK, classic 4-way handshake. The workhorse for ~20 years. Caveat: management frames can be unprotected unless **802.11w (PMF)** is enabled.
- **WPA3-Enterprise**: mandates **PMF (802.11w)**, deprecates TKIP, and adds an optional **192-bit mode** ("WPA3-Enterprise 192-bit / CNSA suite"): requires **EAP-TLS only**, **GCMP-256** data encryption, **HMAC-SHA-384**, and **ECDHE/ECDSA P-384 or RSA-3072** certs. Intended for high-assurance (government/finance).
- **Don't confuse the SAE and Enterprise worlds:**
  - **SAE (Simultaneous Authentication of Equals / "Dragonfly")** is **WPA3-Personal** — it replaces the PSK handshake with a PAKE that resists offline dictionary attacks. SAE is *not* used in Enterprise.
  - **OWE (Opportunistic Wireless Encryption, RFC 8110)** = "Enhanced Open" — encrypts *open/guest* networks (no auth, no password) so traffic isn't in the clear. Also not Enterprise auth, but often discussed alongside WPA3.
- Roles: **WPA3-Enterprise** for managed corporate (EAP-TLS), **WPA3-Personal/SAE** for home/small, **OWE** for guest. SecureW2's sweet spot is **WPA3/WPA2-Enterprise with EAP-TLS + Cloud RADIUS**.

### 3. The three roles (802.1X terminology)

```text
 Supplicant            Authenticator                 Authentication Server
 (client/STA)          (AP or WLC)                    (RADIUS / Cloud RADIUS)
   802.11/EAPOL  <---->  802.11 to client side
                         RADIUS to server side  <-->  EAP terminates HERE
```
- **Supplicant** runs the EAP method and holds the credential (cert/password).
- **Authenticator** (AP standalone, or AP + **WLC**): a controlled gatekeeper. Before auth, only EAPOL passes (the **802.1X controlled port** is closed); it relays EAP↔RADIUS and *never sees the credential*. The WLC/AP terminates the 802.11 side and re-encapsulates EAP into RADIUS.
- **Authentication server (RADIUS)** is where EAP **actually terminates** and the decision is made. It returns `Access-Accept` + keying material + policy (VLAN, ACL).

### 4. The complete association → auth → key flow (EAP-TLS example)

```text
[1] 802.11 Discovery/Association
    STA <-> AP: Beacon/Probe -> Open System Auth -> Association Request/Response
    (AKM = 802.1X; AP advertises WPA2/WPA3-Enterprise in RSN IE)
    -> 802.1X controlled port = BLOCKED (only EAPOL allowed)

[2] 802.1X / EAP authentication
    STA --EAPOL-Start--> AP
    AP  --EAP-Request/Identity--> STA
    STA --EAP-Response/Identity(anonymous@realm)--> AP
        AP wraps EAP in RADIUS Access-Request --> RADIUS
    <==== EAP-TLS full mutual handshake, tunneled EAPOL<->RADIUS ====>
        (ClientHello..Finished; client cert + server cert validated both ways)
    RADIUS --Access-Accept--> AP
        Access-Accept carries:
          - EAP-Success
          - MSK in MS-MPPE-Send-Key / MS-MPPE-Recv-Key (enc. w/ RADIUS shared secret)
          - Tunnel-Type=VLAN, Tunnel-Private-Group-ID=<vlan>, Filter-Id=<role/ACL>
    AP --EAP-Success--> STA

[3] Key derivation
    MSK (>=64 bytes, from TLS exporter) --> PMK = first 32 bytes of MSK
    Both STA and AP now hold the SAME PMK (STA derived it locally; AP got MSK from RADIUS)

[4] WPA 4-Way Handshake (EAPOL-Key) — proves both hold PMK, derives session keys
    AP  -> STA  M1: ANonce
    STA -> AP   M2: SNonce + MIC
        PTK = PRF(PMK, ANonce, SNonce, AP-MAC, STA-MAC)
              PTK splits into: KCK (MIC key) | KEK (key-encrypt) | TK (data key)
    AP  -> STA  M3: GTK (group key, encrypted with KEK) + install + MIC
    STA -> AP   M4: ACK + MIC
    -> Keys installed; 802.1X controlled port = OPEN

[5] Encrypted data
    Unicast: encrypted with the per-session TK  (AES-CCMP / WPA3 GCMP-256)
    Broadcast/Multicast: encrypted with the GTK
    DHCP -> in assigned VLAN -> network access
```

Key derivation detail you must know:
- **MSK** is the master key the EAP method exports (for TLS methods, from the TLS master secret). RADIUS transports it.
- **PMK = MSK[0..31]** (the Pairwise Master Key, 256-bit).
- **PTK = PRF-X(PMK, "Pairwise key expansion", min(MAC)||max(MAC) || min(Nonce)||max(Nonce))** — produces **KCK** (integrity of handshake), **KEK** (encrypts GTK in M3), and **TK** (encrypts actual data frames).
- **GTK** is the shared group key for broadcast/multicast, distributed encrypted under KEK in M3.

### 5. Why the 4-way handshake exists even after EAP succeeds

EAP/RADIUS authenticated *identity* and produced a master key (PMK), but:
- It **proves possession of the PMK** to both sides without sending it (via the MIC over fresh nonces).
- It derives a **fresh per-association PTK** (nonces guarantee uniqueness → replay protection, per-session keys).
- It **distributes the GTK** securely.
This is why a stolen PMK alone isn't enough to passively decrypt a session you didn't see handshake — and why capturing the handshake matters for analysis.

### 6. Fast roaming & reauth (don't make users re-do EAP every AP)

Full EAP-TLS on every roam = seconds of latency = dropped VoIP/RTC calls. Mitigations:
- **PMK caching (PMKID)**: STA + AP cache the PMK; on return, skip EAP and go straight to 4-way handshake.
- **OKC (Opportunistic Key Caching)**: WLC shares the cached PMK across its APs, so the STA can fast-resume on a *new* AP it hasn't authenticated to. Proprietary-ish but widely supported.
- **802.11r (Fast BSS Transition / FT)**: standardized key hierarchy (PMK-R0/PMK-R1 anchored at the WLC) enabling sub-50ms roams with a 4-message FT exchange — no re-EAP. Critical for voice/healthcare.
- **Session-Timeout / reauth**: RADIUS can set `Session-Timeout` to force periodic full reauth (re-checks cert validity/revocation) — balance security vs roam pain.

### 7. Why EAP-TLS + Cloud RADIUS = passwordless enterprise Wi-Fi

- The supplicant authenticates with a **client certificate** — no password to phish, leak, or brute-force from a captured handshake.
- **Cloud RADIUS** (managed, multi-tenant, geo-distributed) removes the on-prem NPS/FreeRADIUS box, scales horizontally, and integrates with IdPs and managed PKI for **automatic cert enrollment + revocation**.
- Revoking access = revoke the cert (CRL/OCSP) → instant, per-device, no PSK rotation, no helpdesk password resets.
- You get **per-device identity, dynamic VLAN/role, accounting, and phishing resistance** — the WPA2/3-Enterprise promise actually delivered. This is precisely SecureW2's JoinNow + Cloud RADIUS + managed PKI story.

### 8. Common failures (and the symptom you'll see)

| Failure | Symptom | Root cause |
|---|---|---|
| Server cert untrusted on client | Client prompts/rejects, EAP fails at TLS | Wrong/missing root CA on supplicant; name mismatch |
| Wrong RADIUS shared secret | AP↔RADIUS silently drops; "no response from server" | Shared secret mismatch (AP `Access-Request` discarded) |
| Clock skew | TLS handshake fails ("certificate not yet valid/expired") | NTP off on client/server breaks cert validity window |
| Expired/revoked client cert | EAP-TLS rejected at server | Cert lifecycle/renewal not automated; CRL/OCSP hit |
| VLAN not returned | Auth succeeds but wrong subnet / no DHCP | RADIUS not sending `Tunnel-Private-Group-ID`; AP not honoring it |
| 4-way handshake fails (M3 timeout) | Auth OK then disconnect, "4-way handshake timeout" | PMK mismatch (MSK not delivered / MPPE key decrypt fail), PMF/IE mismatch |
| Roaming drops | Calls drop on AP change | No 802.11r/OKC; full re-EAP each roam |

---

## PRACTICE

### End-to-end deployment checklist

```text
[ ] RADIUS server cert: CN/SAN = radius.example.com, signed by your CA, valid dates, NTP synced
[ ] Clients trust ONLY your CA root/intermediate (pinned), and pin the RADIUS server name
[ ] EAP-TLS: clients enrolled with client certs (SCEP/EST/ACME / managed PKI auto-enroll)
[ ] AP/WLC: RADIUS server IP + auth(1812)/acct(1813) ports + SHARED SECRET match server
[ ] WLAN: WPA2/WPA3-Enterprise (802.1X AKM), PMF as required (mandatory for WPA3)
[ ] RADIUS policy returns: VLAN (Tunnel-Type/Tunnel-Private-Group-ID), role/ACL (Filter-Id)
[ ] Fast roam: 802.11r and/or OKC/PMK caching enabled if voice/RTC
[ ] Revocation: CRL/OCSP reachable from RADIUS; Session-Timeout set
[ ] Accounting enabled (1813) for audit trail
```

### Full eapol_test run (EAP-TLS, as the supplicant)

```text
# wifi-eaptls.conf
network={
    ssid="CORP-SECURE"
    key_mgmt=WPA-EAP
    proto=RSN
    pairwise=CCMP
    eap=TLS
    identity="laptop01@example.com"
    ca_cert="/etc/certs/ca.pem"
    client_cert="/etc/certs/laptop01.pem"
    private_key="/etc/certs/laptop01.key"
    altsubject_match="DNS:radius.example.com"   # pin server name (anti evil-twin)
}
```

```bash
# Drive a full Access-Request/Accept against the RADIUS server:
eapol_test -c wifi-eaptls.conf -a 10.0.0.10 -p 1812 -s 'SuperSharedSecret' -r0 -t 10
# Healthy tail:
#   EAP-TLS: Done
#   CTRL-EVENT-EAP-SUCCESS
#   MPPE keys OK: 1  mismatch: 0     <-- MSK delivered correctly
#   SUCCESS
```

### Wireshark / capture filters

```text
# Wired side (AP <-> RADIUS): see Access-Request/Accept + EAP + MPPE keys
radius
radius && eap

# Wireless side (needs monitor mode): the EAPOL exchange
eapol                                   # EAP over LAN frames
eapol.type == 3                         # EAPOL-Key (the 4-way handshake M1-M4)
wlan.fc.type_subtype == 0x00            # association request
wlan.rsn.akms.type == 1                 # RSN AKM = 802.1X (Enterprise)
wlan.tag.number == 48                   # RSN Information Element

# Identify the 4 handshake messages:
eapol && wlan.da == <AP_MAC>            # M1, M3 from AP; M2, M4 from STA
```

```bash
# tcpdump on the RADIUS server to confirm AP is even reaching it (shared-secret/firewall sanity):
tcpdump -ni any 'udp port 1812 or udp port 1813' -vv
# If you see Access-Request but no Accept/Reject going back -> shared secret or policy issue.
```

### WLC / AP RADIUS config sketch (Cisco-style)

```text
! RADIUS auth + acct server
radius server CLOUD-RADIUS
  address ipv4 10.0.0.10 auth-port 1812 acct-port 1813
  key SuperSharedSecret                 ! MUST match the RADIUS server's client entry

aaa group server radius CORP-AAA
  server name CLOUD-RADIUS

aaa authentication dot1x CORP-DOT1X group CORP-AAA
aaa accounting dot1x CORP-ACCT start-stop group CORP-AAA

! WLAN: WPA2/WPA3-Enterprise (802.1X)
wlan CORP-SECURE 1 CORP-SECURE
  security wpa akm dot1x
  security wpa wpa3                      ! (or wpa2) 
  security pmf mandatory                 ! 802.11w (mandatory for WPA3)
  security dot1x authentication-list CORP-DOT1X
  aaa-override                           ! honor RADIUS-returned VLAN/ACL
  no shutdown

! FreeRADIUS clients.conf side (the AP/WLC as a RADIUS client):
! client wlc-1 { ipaddr = 10.0.0.5  secret = SuperSharedSecret }
```

### RADIUS dynamic VLAN attributes (returned in Access-Accept)

```text
Tunnel-Type = VLAN (13)
Tunnel-Medium-Type = IEEE-802 (6)
Tunnel-Private-Group-Id = "100"     # VLAN ID for this user/device
Filter-Id = "corp-acl"              # optional role/ACL
Session-Timeout = 3600              # force periodic reauth (revalidates cert)
```

**Exercises:**
1. Capture a full EAP-TLS association in Wireshark (monitor mode). Identify: Association, EAPOL-Start, the EAP-TLS handshake, EAP-Success, and the four `eapol.type==3` handshake messages. Mark where the controlled port opens.
2. On the RADIUS side, `tcpdump` the Access-Accept and locate the `MS-MPPE-*-Key` attributes. Explain how this becomes the PMK and then the PTK.
3. Deliberately set the **wrong shared secret** on the AP and observe the failure mode (silent drop). Then break **NTP** on the client and observe the *different* failure (TLS cert validity). Document both symptoms.
4. Enable **802.11r** and roam between two APs while pinging; compare roam time to PMK-caching-only and to full re-EAP. 
5. Configure RADIUS to return VLAN 100 for one cert and VLAN 200 for another; confirm each device lands in the right subnet via DHCP.
6. Stand up the same SSID as **WPA3-Enterprise with PMF mandatory** and verify a WPA2-only client's behavior; explain the transition-mode trade-off.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. In WPA-Enterprise, the AP relays EAP — does the AP ever see the user's password or private key?**
No. The AP/WLC is the **authenticator** and a pass-through: EAP **terminates at the RADIUS server**. The AP only relays EAP between EAPOL (to client) and RADIUS (to server), and at the end receives the **MSK/keying material** — never the credential itself. This is why a compromised AP can't directly harvest credentials in EAP-TLS (and why server-cert validation, done by the *client*, is what protects tunneled methods).

**Q2. Walk the keys from RADIUS to encrypted data.**
RADIUS returns the **MSK** (from the EAP-TLS exporter) inside `MS-MPPE-*-Key`. **PMK = MSK[0..31]**. The 4-way handshake combines PMK + ANonce + SNonce + both MACs to derive the **PTK**, which splits into **KCK** (handshake MIC), **KEK** (encrypts the GTK in M3), and **TK** (encrypts unicast data via AES-CCMP/GCMP). The **GTK** (group key, for broadcast/multicast) is delivered encrypted under KEK. Data then flows encrypted with TK (unicast) / GTK (group).

**Q3. Why do we still need a 4-way handshake after a successful EAP-TLS auth?**
EAP produced the PMK but did not (a) prove *both* sides actually hold it without transmitting it, (b) derive a fresh **per-session** key, or (c) distribute the **group key**. The handshake uses fresh nonces + MICs to mutually prove PMK possession, derive a unique PTK (replay protection), and securely deliver the GTK. Only then does the controlled port open.

**Q4. Is SAE used in WPA3-Enterprise?**
No. **SAE is WPA3-Personal** (a PAKE replacing the PSK handshake to stop offline dictionary attacks). **Enterprise** uses 802.1X/EAP with RADIUS. Mixing them up is a classic trap. **OWE** ("Enhanced Open") is yet another thing — encryption for *open guest* networks, no auth.

**Q5. What is WPA3-Enterprise 192-bit mode and what does it force?**
The CNSA "192-bit" suite mandates **EAP-TLS only**, **GCMP-256** encryption, **HMAC-SHA-384**, and **P-384/RSA-3072** certs, plus PMF. It's for high-assurance environments. Note it *requires* certificate-based EAP-TLS — passwords/PEAP aren't allowed — reinforcing that the high-security path is passwordless.

**Q6. Auth succeeds but the user has no network / wrong subnet. Where do you look?**
Auth working means EAP + 4-way handshake completed. A wrong/missing subnet points to **authorization/VLAN assignment**: is RADIUS returning `Tunnel-Type=VLAN` + `Tunnel-Private-Group-Id`? Is the WLC honoring it (`aaa-override`)? Does that VLAN exist/trunk to the AP with a DHCP scope? Auth ≠ authorization.

**Q7. Clients intermittently fail TLS with "certificate expired/not yet valid" but the cert dates look fine. Cause?**
**Clock skew.** TLS validates the cert against the local clock; if client or server **NTP** is wrong, a valid cert appears outside its window and the handshake fails. Fix time sync. (This also silently breaks OCSP/CRL freshness checks.)

**Q8. Why is fast roaming a security/operations balancing act, and what tools solve it?**
Full EAP-TLS per roam adds round-trips to RADIUS → seconds of interruption → dropped voice/RTC. **PMK caching**, **OKC**, and **802.11r (FT)** let the STA skip re-EAP and resume with a cached/derived key hierarchy. The trade-off: longer key caching / fewer reauths means a revoked cert keeps working until the cached PMK / `Session-Timeout` expires — so tune `Session-Timeout` against roam UX.

**Q9. Pitch WPA3-Enterprise + EAP-TLS + Cloud RADIUS over WPA2-PSK to a skeptical IT lead.**
PSK shares one crackable secret with everyone; leak/employee-departure forces an org-wide re-key, there's no per-user identity, accounting, or targeted revocation, and a sniffed handshake can be brute-forced offline. EAP-TLS gives every device a **unique, revocable certificate** (no phishable password), **per-session keys**, **dynamic VLAN/role + accounting**, and instant per-device deauthorization via revocation. With **Cloud RADIUS + managed PKI + self-service onboarding**, enrollment and renewal are automatic — you get higher security *and* lower operational cost than the PSK you're defending.

➡ Next: [Day 18 — Identity Providers & Federation: SAML & OIDC](day-18-identity-providers-federation-saml-oidc.md)
