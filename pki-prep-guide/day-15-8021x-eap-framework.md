# Day 15 — 802.1X Port-Based Access Control & the EAP Framework

Day 14 took apart the RADIUS packet. But RADIUS never talks to the endpoint directly — between the laptop and the RADIUS server sits the switch or access point, and the protocol on *that* first hop is **IEEE 802.1X**, carrying **EAP** over the LAN. Today we nail the three roles, the controlled/uncontrolled port model, EAPOL framing, and the EAP framework itself (RFC 3748) — including the all-important outer-vs-inner identity that makes identity privacy and realm routing work. This is the wire-level foundation for every cert-based Wi-Fi/Ethernet deployment SecureW2 enables; Day 16 then drills into the specific EAP methods.

---

## THEORY

### 1. The three roles of 802.1X

IEEE 802.1X is **port-based network access control (PNAC)** — it gates traffic at the Layer-2 port until the endpoint authenticates. Three roles:

| Role | Who | Job |
|------|-----|-----|
| **Supplicant** | The endpoint's 802.1X software (Windows native, wpa_supplicant, macOS, intune-managed, the SecureW2 client) | Proves identity to get on the network. |
| **Authenticator** | The switch (wired) or AP/WLC (wireless) | The "bouncer" at the port. It relays EAP but makes **no auth decision itself**. |
| **Authentication Server (AS)** | RADIUS server (FreeRADIUS, NPS, ISE, **SecureW2 Cloud RADIUS**) | Actually validates the credential/certificate and returns Accept/Reject + authorization AVPs. |

> **Mental model:** the Authenticator is a *pass-through relay/PEP (policy enforcement point)*; the AS is the *PDP (policy decision point)*. The supplicant and the AS run the real cryptographic conversation; the authenticator just shuttles bytes between two transports.

### 2. Controlled vs uncontrolled port

802.1X models each port as **two logical ports**:

- **Uncontrolled port** — always open, but passes **only EAPOL** frames (and a few control protocols). This is how the supplicant can authenticate *before* it has general network access.
- **Controlled port** — carries normal data traffic. It starts **blocked** (Force-Unauthorized) and opens only after a successful authentication; then it can be opened with the **authorized VLAN/ACL** the AS returned.

```text
            +-----------------------------------+
 Supplicant |   Authenticator (switch port)     |
   ===EAPOL=>|  [Uncontrolled port] -> EAP relay |==RADIUS==> Auth Server
            |  [Controlled port]  = BLOCKED      |
            |     ...on Accept... = OPEN (VLAN n)|
            +-----------------------------------+
```

> **Why it matters:** This split is the whole trick — you can speak just enough protocol (EAPOL) to authenticate while no data traffic is allowed. Failed/never-authenticated ports stay blocked (or fall to a guest/quarantine VLAN, depending on config).

### 3. EAPOL — EAP over LAN (the wire protocol)

802.1X defines **EAPOL** (EtherType **0x888E**) to carry EAP between supplicant and authenticator on the LAN. EAPOL frame types:

| EAPOL Type | Name | Purpose |
|------------|------|---------|
| 1 | **EAPOL-Start** | Supplicant announces it wants to authenticate (optional — authenticator may also initiate with an EAP-Request/Identity). |
| 0 | **EAPOL-EAP (EAP-Packet)** | Carries an actual EAP message (Request/Response/Success/Failure). The workhorse. |
| 2 | **EAPOL-Logoff** | Supplicant says "I'm leaving" → port returns to unauthorized. |
| 3 | **EAPOL-Key** | Carries key material — on Wi-Fi this is the **4-Way Handshake** (WPA2/WPA3) that installs the PTK/GTK after EAP succeeds. |
| 4 | EAPOL-Encapsulated-ASF-Alert | Rare, alerting. |

Typical wired/wireless flow on the EAPOL side:

```text
Supplicant                         Authenticator
   |---- EAPOL-Start --------------->|        (or authenticator starts)
   |<--- EAP-Request/Identity -------|
   |---- EAP-Response/Identity ----->|        (outer identity here)
   |<--- EAP-Request (method) -------|  <----\
   |---- EAP-Response (method) ----->|  -----/  (relayed to RADIUS as EAP-Message)
   |          ... method round trips ...
   |<--- EAP-Success ----------------|
   |<==== EAPOL-Key (4-Way HS) ======|        (Wi-Fi: install session keys)
   |   [controlled port now OPEN]    |
```

> **Gotcha:** EAP-Success/Failure carry **no integrity protection of their own**. On Wi-Fi the trust comes from the keys derived during the EAP method and confirmed in the 4-Way Handshake — a spoofed EAP-Success can't produce the right keys, so the handshake fails. This is why "tunneled" methods and proper key derivation matter.

### 4. The two transports: 802.1X (L2) vs RADIUS (L3) — and how they join

This is the single most important architectural point of the day:

```text
  Supplicant  <==== EAPOL (Layer 2, EtherType 0x888E) ====>  Authenticator
  Authenticator <==== RADIUS/UDP or RadSec/TLS (Layer 3) ====>  Auth Server

  The SAME EAP messages ride inside BOTH transports:
     EAP-in-EAPOL  on the wire   <-- relayed by authenticator -->  EAP-in-RADIUS(EAP-Message attr 79)
```

- The authenticator **decapsulates** EAP from EAPOL and **re-encapsulates** it into the RADIUS **EAP-Message (attr 79)** attribute (Day 14), and vice-versa for the return path.
- The authenticator **does not understand the EAP method** (EAP-TLS, PEAP, etc.). It blindly relays. The real cryptographic conversation is **end-to-end between supplicant and AS**.
- Each EAP round trip from the AS arrives as a RADIUS **Access-Challenge** (with State, Day 14); the final result is **Access-Accept → EAP-Success** or **Access-Reject → EAP-Failure**.
- On Accept, the AS also returns the **session keys** to the authenticator via **MS-MPPE-Recv/Send-Key** VSAs, which the AP uses to seed the Wi-Fi 4-Way Handshake.

> **Interview gold:** "Where does the EAP method actually terminate?" → between the **supplicant and the Authentication Server**, *not* at the switch/AP. The authenticator is a dumb relay.

### 5. EAP is a framework, not a method (RFC 3748)

EAP (Extensible Authentication Protocol) defines only **four message types**:

| Code | Type | Meaning |
|------|------|---------|
| 1 | **Request** | AS/authenticator asks for something (Identity, or a method-specific message). |
| 2 | **Response** | Supplicant answers. |
| 3 | **Success** | Authentication succeeded. |
| 4 | **Failure** | Authentication failed. |

Inside Request/Response is a **Type** field selecting what's being negotiated/run:

- **Type 1 = Identity**, Type 2 = Notification, Type 3 = **Nak** (used to *reject* a proposed method and propose another → this is method negotiation).
- **Type 13 = EAP-TLS**, 25 = PEAP, 21 = EAP-TTLS, 50/55 = EAP-TEAP, 18 = EAP-SIM, 23 = EAP-AKA, etc. (Day 16).

So EAP itself doesn't authenticate anything — it's a **negotiation + transport framework**, and the actual authentication method (certificates in EAP-TLS, MSCHAPv2 inside PEAP/TTLS) **rides inside** it.

**Method negotiation:** AS proposes a method (EAP-Request/Type=X); if the supplicant can't/won't do X, it sends an **EAP-Nak** listing acceptable types; the AS picks one or rejects. This is how a server says "I want EAP-TLS" and a client agrees (or downgrades — which is also a security concern: pin the method, don't allow weak fallbacks).

### 6. EAP identity — outer vs inner (identity privacy)

The very first thing exchanged is the **EAP-Identity** (Type 1). In tunneled methods there are **two** identities:

- **Outer identity** — sent in the *cleartext* EAP-Response/Identity and copied into the RADIUS **User-Name**. It's used for **realm routing/proxying** (Day 14). Best practice: make it **anonymous**, e.g. `anonymous@example.edu` — reveal only the realm, not the user.
- **Inner identity** — the *real* username/UPN, exchanged **inside the encrypted TLS tunnel** (PEAP/TTLS/TEAP) where eavesdroppers can't see it. The home AS authenticates against this.

```text
Cleartext on wire:  User-Name = anonymous@corp.example   <- routes to corp.example
Inside TLS tunnel:  inner identity = alice@corp.example   <- actually authenticated
```

- **EAP-TLS** is special: identity is the **certificate** itself (the SAN/Subject), so there's no password to hide — though you can still use an anonymous outer identity to avoid leaking the username in the cleartext Identity exchange.

> **SecureW2 context:** Identity privacy matters in federations (eduroam) and on hostile Wi-Fi. SecureW2's cert-based EAP-TLS removes the password entirely; the "identity" is the certificate's SAN (UPN/email), validated by Cloud RADIUS, and policy/VLAN is driven off cert attributes — no credential ever traverses the air in any form.

### 7. The full chain end-to-end

```text
[Endpoint/Supplicant]
      |  EAPOL (0x888E, L2)            <-- only this is allowed pre-auth (uncontrolled port)
      v
[Switch/AP = Authenticator]
      |  RADIUS Access-Request/Challenge, EAP-Message attr 79, over UDP 1812 or RadSec TCP 2083
      v
[RADIUS / SecureW2 Cloud RADIUS = Authentication Server]
      |  validates cert/credential, checks CRL/OCSP, runs policy
      v
   Access-Accept  + VLAN/ACL AVPs + MS-MPPE keys   --->  EAP-Success to supplicant
                                                          controlled port opens
```

Memorize the encapsulation: **method-inside-EAP**, **EAP-inside-EAPOL** (wire) / **EAP-inside-RADIUS** (uplink), authenticator bridges the two transports.

### 8. MAC Authentication Bypass (MAB) — for devices that can't do 802.1X

Printers, IoT, cameras, badge readers often have **no supplicant**. **MAB** lets the authenticator authenticate them by **MAC address**:

- The port waits for EAPOL; if it hears none (timeout), it falls back to MAB.
- The switch learns the source MAC and sends a RADIUS **Access-Request** using the MAC as **User-Name *and* User-Password** (or Calling-Station-Id), with **Service-Type = Call-Check (10)** to signal "this is a MAC-auth, not a real EAP session."
- The AS checks the MAC against an allow-list/IoT inventory and returns Accept (often onto a restricted IoT VLAN) or Reject.

> **Security gotcha:** MAC addresses are trivially spoofable, so MAB is **weak** — always pair it with tight VLAN segmentation, device profiling (DHCP/HTTP fingerprinting), and ideally move device classes to **certificate-based onboarding** where possible. Best practice: try 802.1X first, **fall back** to MAB only for known no-supplicant devices.

### 9. Wired vs wireless 802.1X — same EAP, different L2 specifics

| Aspect | Wired (switch) | Wireless (AP/WLC) |
|--------|----------------|-------------------|
| Transport of EAPOL | Ethernet frames on the port | 802.11 data frames |
| Post-auth key step | Usually none (port just opens) | **4-Way Handshake (EAPOL-Key)** installs PTK/GTK for over-the-air encryption |
| Trigger | Link-up; supplicant sends EAPOL-Start or switch sends EAP-Request/Identity | Association to the WPA-Enterprise SSID |
| Failure handling | Auth-fail VLAN / guest VLAN / port stays down | Deauth / fall to open or fail |
| Physical assumption | "If you're plugged in you're somewhat trusted" — but 802.1X removes that assumption | Air is inherently open, so encryption is mandatory |

> **Key difference:** Wireless *must* derive and install session keys (the EAPOL-Key 4-Way Handshake) because the medium is open; wired 802.1X typically just unblocks the controlled port. Same EAP method runs either way.

---

## PRACTICE

### A. Read EAPOL/EAP in Wireshark

```text
# Capture on the client NIC or a mirrored switch port.

# Display filters:
eapol                      # all EAPOL frames (EtherType 0x888E)
eap                        # the EAP messages carried inside
eap.code == 1              # EAP Requests
eap.code == 2              # EAP Responses
eap.code == 3              # EAP Success
eap.code == 4              # EAP Failure
eap.type == 1              # EAP-Identity exchanges (see the OUTER identity here)
eap.type == 13             # EAP-TLS
eapol.type == 1            # EAPOL-Start
eapol.type == 3            # EAPOL-Key (the Wi-Fi 4-Way Handshake)

# What to look for, in order:
#  1. EAPOL-Start (or first EAP-Request/Identity from the authenticator)
#  2. EAP-Response/Identity  -> note it shows "anonymous@realm" if privacy is on
#  3. EAP method round-trips (e.g., TLS handshake under eap.type==13)
#  4. EAP-Success, then (Wi-Fi) four EAPOL-Key messages (msg 1/2/3/4 of 4-Way HS)
```

```bash
# tshark equivalent (CLI) on wlan/eth interface:
sudo tshark -i wlan0 -Y "eapol || eap" -O eap,eapol
# Or filter just identities to see outer identity privacy in action:
sudo tshark -i eth0 -Y "eap.type == 1" -T fields -e eap.identity
```

### B. Sample Cisco IOS switchport for 802.1X (+ MAB fallback)

```text
! --- Global AAA + RADIUS (use RadSec/dot1x server in production) ---
aaa new-model
radius server CLOUD-RADIUS
 address ipv4 10.0.0.10 auth-port 1812 acct-port 1813
 key 7 <shared-secret>          ! or configure RadSec/dtls
aaa authentication dot1x default group radius
aaa authorization network default group radius
aaa accounting dot1x default start-stop group radius
dot1x system-auth-control       ! globally enable 802.1X

! --- Access port: 802.1X first, fall back to MAB ---
interface GigabitEthernet1/0/10
 switchport mode access
 authentication port-control auto          ! enforce 802.1X (controlled port)
 authentication host-mode multi-auth       ! per-MAC auth (phone+PC, etc.)
 authentication order dot1x mab            ! try 802.1X, then MAB
 authentication priority dot1x mab
 dot1x pae authenticator
 dot1x timeout tx-period 7
 mab                                        ! enable MAC Auth Bypass
 authentication event fail action authorize vlan 999   ! auth-fail VLAN
 authentication periodic                    ! periodic reauth
 authentication timer reauthenticate server ! reauth interval from RADIUS (Session-Timeout)
 spanning-tree portfast
```

```text
! Verify:
show authentication sessions interface Gi1/0/10 details
show dot1x interface Gi1/0/10 details
! Look for: Method (dot1x/mab), State (Authz Success), assigned VLAN, the client MAC.
```

### C. FreeRADIUS EAP module overview (server side)

```text
# /etc/freeradius/3.0/mods-enabled/eap  (key directives, abbreviated)
eap {
    default_eap_type = tls          # prefer EAP-TLS (cert-based) — Day 16
    timer_expire     = 60
    ignore_unknown_eap_types = no
    # cisco_accounting_username_bug = no

    tls-config tls-common {
        private_key_file = /etc/freeradius/3.0/certs/server.key
        certificate_file = /etc/freeradius/3.0/certs/server.crt
        ca_file          = /etc/freeradius/3.0/certs/ca.crt   # validate CLIENT certs against this CA
        # CRL / OCSP for revocation checking (Day 9-10):
        check_crl = yes
        ocsp { enable = yes  override_cert_url = yes  url = "http://ocsp.example/" }
    }

    tls { tls = tls-common }        # EAP-TLS
    peap {                          # PEAP wraps an inner EAP method in TLS
        tls = tls-common
        default_eap_type = mschapv2
    }
    ttls {                          # EAP-TTLS
        tls = tls-common
        default_eap_type = mschapv2
        copy_request_to_tunnel = yes
        use_tunneled_reply = yes    # let inner auth's reply attrs (VLAN!) propagate out
    }
}
```

```bash
# Run FreeRADIUS in foreground debug to watch the full EAP/RADIUS conversation:
sudo freeradius -X
# You'll see: Access-Request -> Access-Challenge (per EAP round trip, with State) -> Access-Accept/EAP-Success.
```

**Exercises:**

1. Capture a full 802.1X association in Wireshark; mark exactly where EAPOL ends and (on Wi-Fi) the 4-Way Handshake begins. How many EAPOL-Key frames are there?
2. With identity privacy enabled, prove via `eap.type == 1` filter that the cleartext Identity is `anonymous@realm`, and explain where the *real* identity travels.
3. Configure a switchport to try 802.1X then MAB; force a no-supplicant device and confirm via `show authentication sessions` that it landed via MAB on the IoT VLAN.
4. In `freeradius -X`, identify each Access-Challenge round trip and the **State** attribute correlating them.
5. Explain, frame by frame, why a forged EAP-Success can't get an attacker onto a WPA2-Enterprise network (hint: the 4-Way Handshake).
6. Modify the EAP module to require EAP-TLS only (no PEAP/TTLS fallback) and describe the security benefit and the deployment cost.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Where does the EAP authentication method actually terminate — the switch or the RADIUS server?**
At the **Authentication Server (RADIUS)**, end-to-end with the **supplicant**. The authenticator (switch/AP) is a **dumb relay**: it decapsulates EAP from EAPOL and re-encapsulates it into the RADIUS EAP-Message attribute and back, but it never parses or validates the EAP method (TLS handshake, MSCHAPv2, etc.). That's why you can swap RADIUS back ends without touching the switch's EAP logic.

**Q2. Explain controlled vs uncontrolled ports.**
802.1X splits each physical port into two logical ports. The **uncontrolled** port is always up but passes **only EAPOL** — just enough to authenticate. The **controlled** port carries data traffic and starts **blocked**; it opens only after Access-Accept, applying the authorized VLAN/ACL. This lets a device authenticate while having zero data-plane access.

**Q3. "EAP is a framework, not a method." What does that mean concretely?**
EAP (RFC 3748) defines only Request/Response/Success/Failure messages plus a **Type** field for negotiation. It performs **no authentication itself** — it transports and negotiates an inner *method* (EAP-TLS, PEAP, TTLS, TEAP, SIM/AKA…). The method does the real crypto; EAP just frames it and handles selection (via EAP-Nak) and round-tripping.

**Q4. Outer vs inner identity — why have both, and which one shows up in the RADIUS User-Name?**
The **outer identity** is cleartext, copied into RADIUS **User-Name**, and used for **realm routing/proxying** — so you set it to `anonymous@realm` to leak only the realm. The **inner identity** (the real UPN/username) travels **inside the encrypted TLS tunnel** of PEAP/TTLS/TEAP, hidden from eavesdroppers, and is what the home server authenticates. This gives identity privacy while still allowing federated routing (eduroam).

**Q5. A non-802.1X printer needs network access. How do you authenticate it and what's the risk?**
Use **MAB (MAC Authentication Bypass)**: after the EAPOL timeout, the switch sends a RADIUS request with the device's **MAC as User-Name (and password)** and **Service-Type = Call-Check**; the AS checks an allow-list and returns a restricted VLAN. The risk is that **MACs are spoofable**, so MAB is weak — mitigate with strict segmentation, device profiling/fingerprinting, and moving to certificates where the device supports it. Always order `dot1x` before `mab`.

**Q6. On Wi-Fi, after EAP-Success why isn't the client immediately on the network?**
Because the open medium requires session encryption. After EAP-Success the AS delivers keying material (MS-MPPE keys) to the AP, and the supplicant and AP run the **4-Way Handshake (EAPOL-Key)** to derive/install the PTK/GTK. Only after the 4-Way Handshake completes is the controlled port truly usable. This also defeats spoofed EAP-Success frames — without the correct master key the handshake fails.

**Q7. What's EAPOL and why does it exist instead of just using RADIUS to the client?**
**EAPOL (EAP over LAN, EtherType 0x888E)** is the L2 encapsulation that carries EAP between supplicant and authenticator *before* the client has any IP connectivity. RADIUS is an IP/UDP (or TLS) protocol and needs L3 — the unauthenticated client has no IP yet, so you can't use RADIUS to it. EAPOL works at Layer 2 over the (otherwise blocked) port; the authenticator then bridges EAP into RADIUS toward the server.

**Q8. How does method negotiation / downgrade work, and why is it a security concern?**
The AS proposes an EAP method (EAP-Request/Type=X). If unacceptable, the supplicant returns an **EAP-Nak** listing methods it supports; the AS picks one or rejects. The risk is a **downgrade**: if you allow weak fallbacks (e.g., bare MSCHAPv2 or LEAP), an attacker or misconfiguration can negotiate the weakest mutually-supported method. Best practice: **pin a strong method** (EAP-TLS) and disable weak alternatives on both supplicant and server.

**Q9. Map each piece of the chain to a transport and a port number.**
Supplicant ↔ Authenticator: **EAPOL at Layer 2**, EtherType **0x888E** (no IP port). Authenticator ↔ Auth Server: **RADIUS** over **UDP 1812** (auth) / **1813** (accounting), or **RadSec** over **TCP 2083** / RADIUS-DTLS **UDP 2083**; CoA/Disconnect on **UDP 3799**. The same EAP messages ride inside both the EAPOL (wire) and the RADIUS EAP-Message attribute (uplink).

---

➡ Next: [Day 16 — EAP Methods Compared: EAP-TLS, PEAP, EAP-TTLS & TEAP](day-16-eap-methods-eap-tls-peap-ttls-teap.md)
