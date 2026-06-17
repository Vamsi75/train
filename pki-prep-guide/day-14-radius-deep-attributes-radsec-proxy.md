# Day 14 — RADIUS Deep Dive: Attributes, RadSec, Proxy & Accounting

By now you know RADIUS is the AAA (Authentication, Authorization, Accounting) protocol that lives behind every 802.1X deployment. Today we go *inside* the packet: the Attribute-Value Pairs (AVPs) that carry the real intelligence, how vendors extend RADIUS, how authorization decisions (VLAN, ACL, session limits) are pushed back to the switch/AP, how accounting tracks a session, and — critically for cloud-era PKI — how RadSec fixes RADIUS's 1990s security model. This is the protocol layer that makes SecureW2 Cloud RADIUS work over the public internet.

---

## THEORY

### 1. The RADIUS packet & where AVPs live

A RADIUS packet (RFC 2865) has a fixed 20-byte header followed by a variable list of attributes:

```text
 0                   1                   2                   3
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|     Code      |  Identifier   |            Length             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
|                  Authenticator (16 bytes)                     |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Attributes ...  (Type | Length | Value) (Type | Length | ...)|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Code** — the message type: `Access-Request` (1), `Access-Accept` (2), `Access-Reject` (3), `Accounting-Request` (4), `Accounting-Response` (5), `Access-Challenge` (11), plus CoA/Disconnect (40–45).
- **Identifier** — matches a response to its request (an 8-bit counter; wraps fast under load — a real scaling gotcha).
- **Authenticator** — 16 bytes. In requests it's the *Request Authenticator* (random nonce); in responses it's the *Response Authenticator* = `MD5(Code+ID+Length+RequestAuth+Attributes+SharedSecret)`. This is the only built-in integrity check, and it's **MD5-based** — remember that for the RadSec discussion.
- **Attributes** — the payload. Each AVP is **Type (1 byte) | Length (1 byte) | Value**. Because Length is one byte, a single attribute caps at **253 bytes of value** — long values (EAP, certs) must be *fragmented* across multiple attributes of the same type.

> **Why it matters:** Everything interesting — who the user is, what AP they hit, what VLAN to assign — is an AVP, not a header field. RADIUS is essentially "a header plus a bag of attributes."

### 2. Common standard attributes (the ones you'll see daily)

| Attr # | Name | Direction | Meaning / gotcha |
|--------|------|-----------|------------------|
| 1 | **User-Name** | Request | The identity. For EAP this is the **outer** (anonymous) identity, e.g. `anonymous@realm` — see Day 15 on identity privacy. |
| 4 | **NAS-IP-Address** | Request | IPv4 of the Authenticator (switch/AP/controller). Used with NAS-Identifier to identify the device sending the request. |
| 5 | NAS-Port | Request | Physical/virtual port number. |
| 6 | **Service-Type** | Both | Requested service: `Framed` (2), `Login`, `Call-Check` (10 — used for MAB), etc. |
| 30 | **Called-Station-Id** | Request | The **AP/NAS MAC** (and often SSID appended, e.g. `aabbcc-ddeeff:CorpWiFi`). "Called" = the thing the client dialed into. |
| 31 | **Calling-Station-Id** | Request | The **client/endpoint MAC**. "Calling" = who's calling in. Memorize this pair — it trips up everyone. |
| 32 | NAS-Identifier | Request | String name of the NAS (alternative to NAS-IP-Address). |
| 61 | **NAS-Port-Type** | Request | `Ethernet` (15), `Wireless-802.11` (19), `Virtual`. Lets policy distinguish wired vs Wi-Fi. |
| 7/8 | Framed-Protocol / Framed-IP-Address | Both | Legacy dial framing; Framed-IP-Address still used to assign/learn client IP. |
| 79 | **EAP-Message** | Both | Carries one EAP fragment. Repeated/concatenated when EAP exceeds 253 bytes. The heart of 802.1X. |
| 80 | **Message-Authenticator** | Both | **HMAC-MD5** over the whole packet keyed by the shared secret. MANDATORY whenever EAP-Message is present — it's the real integrity protection for EAP packets, and the 2024 **BlastRADIUS** (CVE-2024-3596) attack exploited servers that didn't enforce it. Always require it. |
| 24 | **State** | Both | Opaque server-issued cookie that ties a multi-round-trip conversation (Access-Challenge ↔ Access-Request) together. The client must echo it back unchanged. |

> **Gotcha — Called vs Calling:** Called-Station-Id = AP MAC (+SSID). Calling-Station-Id = client MAC. Interviewers love asking "which one is the client?" The answer is **Calling**.

### 3. Authorization attributes — pushing policy back to the NAS

An `Access-Accept` isn't just "yes." It can carry *authorization* attributes that tell the switch/AP exactly how to treat the session. The big ones:

**Dynamic VLAN assignment (RFC 3580 / 4675)** — three attributes always travel together:

| Attr | Name | Value for VLAN |
|------|------|----------------|
| 64 | **Tunnel-Type** | `VLAN` (13) |
| 65 | **Tunnel-Medium-Type** | `IEEE-802` (6) |
| 81 | **Tunnel-Private-Group-Id** | the VLAN ID or name, e.g. `"30"` or `"Employees"` |

All three with the **same Tag byte** (high byte of the value, used to group tagged attributes). Send Tunnel-Private-Group-Id without the other two and most switches silently ignore it — a classic dynamic-VLAN debugging session.

**Other authorization attributes:**

- **Filter-Id (11)** — names a pre-configured ACL on the switch to apply to the session (e.g. `quarantine-acl`).
- **Session-Timeout (27)** + **Termination-Action (29)** — force re-auth after N seconds. `Termination-Action = RADIUS-Request (1)` means "re-authenticate" rather than "drop"; that's how you implement periodic **reauthentication** without dropping the user.
- **Idle-Timeout (28)** — disconnect after inactivity.
- **Egress-VLANID / Egress-VLAN-Name (56/58)**, **NAS-Filter-Rule (92)**, vendor ACL attributes — finer-grained per-vendor controls.
- **Acct-Interim-Interval (85)** — server tells the NAS how often to send interim accounting updates.

> **SecureW2 context:** In Cloud RADIUS, these authorization attributes are driven by **policy engine rules** that read the *client certificate* (and optionally a live lookup into Azure AD / Entra ID, Okta, Google). Example: "if cert SAN UPN is in the `Contractors` group → return Tunnel-Private-Group-Id = 50 + Filter-Id = restricted." This is policy-based VLAN steering off certificate attributes — no password, no live IdP dependency at auth time.

### 4. Vendor-Specific Attributes (VSAs) and the dictionary

Standard attribute numbers are scarce, so RFC 2865 reserves **Type 26 (Vendor-Specific)** as an escape hatch. A VSA wraps:

```text
Type=26 | Length | Vendor-Id (4 bytes, IANA PEN) | Vendor-Type | Vendor-Length | Value
```

- **Vendor-Id** is the vendor's IANA Private Enterprise Number (Cisco = 9, Aruba/HPE = 14823, Microsoft = 311, Meraki under Cisco, etc.).
- Examples: `Cisco-AVPair` (heavily used — `cisco-avpair="device-traffic-class=voice"`, downloadable ACLs, dACL names), `Aruba-User-Role`, `MS-MPPE-Recv-Key`/`MS-MPPE-Send-Key` (how the 802.1X session key is delivered to the AP).

**The dictionary** is how a RADIUS server maps human names ↔ numeric (Type, Vendor) tuples. In FreeRADIUS, `/usr/share/freeradius/dictionary*` defines them:

```text
# dictionary.cisco (excerpt)
VENDOR          Cisco           9
BEGIN-VENDOR    Cisco
ATTRIBUTE       Cisco-AVPair    1   string
END-VENDOR      Cisco
```

> **Gotcha:** If a VSA isn't in the dictionary, the server logs it as `Attribute-26.<vendorid>.<type>` raw hex and can't act on it. Adding the right vendor dictionary is step one when integrating a new NAS.

### 5. RADIUS accounting (RFC 2866)

Authentication says *who*; accounting says *what happened and for how long*. The NAS sends `Accounting-Request` packets to UDP **1813** (auth is **1812**):

| Acct-Status-Type (40) | When | Carries |
|-----------------------|------|---------|
| **Start (1)** | Session comes up | Acct-Session-Id, User-Name, framed IP, Calling-Station-Id |
| **Interim-Update (3)** | Every Acct-Interim-Interval | Running counters (Input/Output-Octets, Packets, Acct-Session-Time) |
| **Stop (2)** | Session ends | Final octet/packet counts, **Acct-Terminate-Cause (49)** (User-Request, Lost-Carrier, Session-Timeout, Admin-Reset…) |

Key accounting AVPs: **Acct-Session-Id (44)** (unique per session — your correlation key), **Acct-Session-Time (46)**, **Acct-Input/Output-Octets (42/43)** plus **-Gigawords (52/53)** for >4 GB sessions (octets are 32-bit!), **Acct-Multi-Session-Id (50)** to stitch roaming sessions.

> **Why it matters:** Accounting Start records carry the framed IP + MAC + username at one point in time — that's the source-of-truth for "who had IP x.x.x.x at 14:32," feeding SIEM, NAC, and forensic correlation. SecureW2 surfaces these as connection logs tied to the certificate identity.

### 6. RADIUS's security problems → RadSec

Classic RADIUS was designed for a trusted LAN between NAS and server. Its weaknesses:

1. **UDP transport** — no reliable delivery, no congestion control, retransmits at the app layer; the 8-bit Identifier limits in-flight requests per src/dst tuple.
2. **MD5 everywhere** — Response Authenticator and the password-hiding for User-Password use MD5. MD5 is cryptographically broken; **BlastRADIUS (CVE-2024-3596, 2024)** showed an attacker who can MITM RADIUS/UDP can forge an Access-Accept by exploiting MD5 collisions in the Response Authenticator. Mitigation: mandatory Message-Authenticator (HMAC) on all packets, or move off UDP entirely.
3. **Shared secret** — a single static PSK per NAS, often weak, often reused, never rotated. Compromise it and you can decrypt/forge.
4. **Only User-Password is "encrypted"** (XOR-with-MD5-keystream); everything else — User-Name, MAC, VSAs — is **cleartext** on the wire.

**RadSec — RADIUS over TLS (RFC 6614), TCP port 2083:**

- Wraps the entire RADIUS exchange in a **TLS tunnel** → confidentiality, integrity, and **mutual certificate authentication** between RADIUS peers (client and server present X.509 certs).
- **TCP** gives reliable, ordered delivery; the Identifier-exhaustion problem largely goes away.
- The legacy shared secret is reduced to the fixed string `"radsec"` — trust now comes from the TLS certificate, not a PSK.
- **RADIUS/DTLS (RFC 7360)** is the UDP-based sibling: same TLS protection over datagrams, UDP 2083 — used where stateful TCP is undesirable.

> **Why Cloud RADIUS needs RadSec:** Cleartext UDP RADIUS over the public internet is a non-starter — secrets and identities exposed, spoofable, MD5-forgeable. SecureW2 Cloud RADIUS uses **RadSec** so an on-prem AP/controller connects to the cloud RADIUS service over a mutually-authenticated TLS tunnel on TCP 2083. Many vendors (Aruba, Cisco, Meraki, Ruckus, Mist) support RadSec natively or via a lightweight **RadSec proxy** running on-prem that converts local UDP RADIUS ↔ outbound RadSec.

### 7. Proxying, realms & eduroam

A RADIUS server can act as a **proxy**: receive an Access-Request and forward it to another server based on the **realm** parsed from User-Name.

- **Realm** = the part after `@` (or before `\` in `DOMAIN\user`). `alice@example.edu` → realm `example.edu`.
- The proxy strips/keeps the realm, picks an upstream **home server** from a realm→server mapping, and relays. The reply travels back through the same chain (each hop re-signs with its own shared secret or its own RadSec session).
- **Proxy chains** let requests traverse multiple organizations — each hop only trusts its neighbor.

**eduroam is the canonical example:** a global Wi-Fi federation. A student from University A visiting University B associates to `eduroam`; B's RADIUS sees realm `@a.edu`, proxies up to a **national/top-level RADIUS server**, which routes down to A's home server. A authenticates its own user and returns Accept/Reject. The visited site never sees the user's credentials — only the home institution does. eduroam runs the inter-federation links over **RadSec** today, exactly for the transport-security reasons above.

> **Identity-privacy tie-in:** Proxying works on the *outer* identity (`anonymous@a.edu`) so realms route correctly while the real inner identity stays hidden inside the EAP tunnel until it reaches the home server. (Day 15/16.)

### 8. CoA & Disconnect-Message (RFC 5176) — change a live session

Standard RADIUS is request-driven by the NAS. RFC 5176 adds **server-initiated** packets to the NAS (UDP **3799**) to modify or kill an *active* session:

- **CoA-Request (43)** — Change of Authorization: re-apply policy to a live session without disconnecting — e.g. move a device to a quarantine VLAN after a posture failure, or bump a guest to a full-access VLAN after they accept terms.
- **Disconnect-Request (40)** (a.k.a. Disconnect-Message / DM) — **forcibly terminate** a session. The NAS replies `Disconnect-ACK (41)` or `Disconnect-NAK (42)`.
- The session is identified by **session-identification attributes** in the CoA/DM packet: Acct-Session-Id, User-Name, Calling-Station-Id (MAC), NAS-IP-Address — the NAS matches them to a live session.

> **Why it matters:** CoA/DM is how you do **dynamic deauth / revocation enforcement at the network edge**. When you revoke a certificate (Day 9–10), the user is still connected until their session re-auths. CoA-Disconnect lets the policy system *immediately* kick that MAC, forcing re-auth — which then fails against the revoked cert. SecureW2 + NAC integrations use CoA to action a revocation in seconds rather than waiting for the next reauth interval.

---

## PRACTICE

We'll use FreeRADIUS tooling (`radclient`, dictionaries) — the de-facto reference RADIUS stack. Commands assume a Linux box with `freeradius-utils` installed.

### A. Explore the dictionaries

```bash
# Where the dictionaries live (Debian/Ubuntu paths)
ls /usr/share/freeradius/
ls /etc/freeradius/3.0/mods-config/

# Find the numeric type of a standard attribute
grep -i "^ATTRIBUTE.*Calling-Station-Id" /usr/share/freeradius/dictionary.rfc2865
# ATTRIBUTE   Calling-Station-Id   31   string

# Inspect a vendor dictionary and its IANA PEN
grep -E "^VENDOR|Cisco-AVPair" /usr/share/freeradius/dictionary.cisco
# VENDOR   Cisco   9
# ATTRIBUTE   Cisco-AVPair   1   string

# List the Tunnel-* attributes used for dynamic VLAN
grep -iE "Tunnel-Type|Tunnel-Medium-Type|Tunnel-Private-Group-Id" /usr/share/freeradius/dictionary.rfc2868
```

### B. Send an Access-Request with radclient (simulate a NAS)

```bash
# radclient reads attribute=value pairs (one per line) from stdin.
# -x = verbose (prints decoded packets), :1812 = auth port.

cat > /tmp/auth.txt <<'EOF'
User-Name = "alice@example.edu"
User-Password = "S3cret!"
NAS-IP-Address = 10.0.0.5
NAS-Port-Type = Wireless-802.11
Calling-Station-Id = "aa-bb-cc-11-22-33"
Called-Station-Id  = "00-11-22-aa-bb-cc:CorpWiFi"
Service-Type = Framed-User
EOF

# Syntax: radclient <server>:<port> <packet-type> <shared-secret>
radclient -x 127.0.0.1:1812 auth testing123 < /tmp/auth.txt
# Look for "Received Access-Accept" or "Access-Reject" and the returned AVPs.
```

### C. Include a VSA in the request

```bash
cat > /tmp/vsa.txt <<'EOF'
User-Name = "switchport-test"
NAS-IP-Address = 10.0.0.5
Cisco-AVPair = "device-traffic-class=voice"
Service-Type = Call-Check
EOF

radclient -x 127.0.0.1:1812 auth testing123 < /tmp/vsa.txt
# The server must have dictionary.cisco loaded or it logs the VSA as raw hex.
```

### D. Configure a dynamic-VLAN reply (server side)

In FreeRADIUS, return the three Tunnel attributes from a `users` file entry or an `unlang` policy. All three share Tag `:1`:

```text
# /etc/freeradius/3.0/mods-config/files/authorize
alice@example.edu  Cleartext-Password := "S3cret!"
        Tunnel-Type = VLAN,
        Tunnel-Medium-Type = IEEE-802,
        Tunnel-Private-Group-Id = "30",
        Session-Timeout = 3600,
        Termination-Action = RADIUS-Request,
        Filter-Id = "employee-acl"
```

```bash
# Reload and test; the Access-Accept should now echo the Tunnel-* AVPs.
sudo systemctl reload freeradius
radclient -x 127.0.0.1:1812 auth testing123 < /tmp/auth.txt | grep -iE "Tunnel|Filter|Session-Timeout"
```

### E. Simulate accounting (Start / Interim / Stop)

```bash
# Accounting goes to port 1813 with packet-type "acct".
SID="sess-$(date +%s)"

# --- Start ---
cat > /tmp/acct.txt <<EOF
Acct-Status-Type = Start
Acct-Session-Id = "$SID"
User-Name = "alice@example.edu"
NAS-IP-Address = 10.0.0.5
Calling-Station-Id = "aa-bb-cc-11-22-33"
Framed-IP-Address = 10.20.30.40
EOF
radclient -x 127.0.0.1:1813 acct testing123 < /tmp/acct.txt

# --- Interim-Update (counters mid-session) ---
cat > /tmp/acct.txt <<EOF
Acct-Status-Type = Interim-Update
Acct-Session-Id = "$SID"
User-Name = "alice@example.edu"
NAS-IP-Address = 10.0.0.5
Acct-Session-Time = 600
Acct-Input-Octets = 1048576
Acct-Output-Octets = 5242880
EOF
radclient -x 127.0.0.1:1813 acct testing123 < /tmp/acct.txt

# --- Stop ---
cat > /tmp/acct.txt <<EOF
Acct-Status-Type = Stop
Acct-Session-Id = "$SID"
User-Name = "alice@example.edu"
NAS-IP-Address = 10.0.0.5
Acct-Session-Time = 1800
Acct-Input-Octets = 3145728
Acct-Output-Octets = 15728640
Acct-Terminate-Cause = User-Request
EOF
radclient -x 127.0.0.1:1813 acct testing123 < /tmp/acct.txt
# Each should return "Received Accounting-Response". Check radacct log / SQL.
```

### F. Peek at RadSec (TCP 2083)

```bash
# Confirm a RadSec listener is up and presenting a server cert:
openssl s_client -connect radsec.example.com:2083 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# A RadSec client must present ITS cert too (mutual TLS):
openssl s_client -connect radsec.example.com:2083 \
  -cert /etc/radsec/client.crt -key /etc/radsec/client.key </dev/null
```

**Exercises:**

1. Capture an `Access-Request` and identify, from the AVPs alone, whether it's wired or wireless, and which value is the client MAC vs the AP MAC.
2. Build a `radclient` request that *omits* `Message-Authenticator` and one that includes it; explain why a hardened server may reject the first (BlastRADIUS).
3. Write a `users`-file entry that puts contractors on VLAN 50 with `Filter-Id=restricted` and a 30-minute Session-Timeout, then prove it via `radclient`.
4. Send Start → 2× Interim → Stop with realistic increasing octet counters using the same Acct-Session-Id; locate the records in the accounting backend.
5. Diagram an eduroam auth for `bob@uni-a.edu` roaming at `uni-b.edu`, labeling each RadSec proxy hop and where the credentials are actually checked.
6. Explain, with the exact session-ID attributes, how a CoA-Disconnect targets *one* device after its cert is revoked.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Calling-Station-Id and Called-Station-Id — which is the client and which is the AP, and why is the naming "backwards"?**
**Calling**-Station-Id = the **client/endpoint MAC** (the station "calling in"); **Called**-Station-Id = the **NAS/AP MAC**, usually with the SSID appended (the station being "called"). The naming comes from RADIUS's dial-up telephony heritage: the caller is the user, the callee is the access server. People expect "Called = the client we're calling," which is the trap.

**Q2. An admin sets `Tunnel-Private-Group-Id = 30` in the Access-Accept but the client lands on the default VLAN. Why?**
Dynamic VLAN requires **all three** attributes together with a matching tag: `Tunnel-Type = VLAN(13)`, `Tunnel-Medium-Type = IEEE-802(6)`, and `Tunnel-Private-Group-Id`. Most switches ignore a lone Tunnel-Private-Group-Id. Secondary causes: the VLAN isn't created/allowed on the switch, the port isn't configured for RADIUS-assigned VLANs, or a tag mismatch across the three attributes.

**Q3. Why is the Message-Authenticator attribute critical, and what real-world attack made it mandatory?**
Message-Authenticator (attr 80) is an **HMAC-MD5** over the whole packet keyed by the shared secret — it provides true integrity, unlike the MD5 Response Authenticator. **BlastRADIUS (CVE-2024-3596, 2024)** lets a MITM forge an Access-Accept from an Access-Reject by exploiting MD5 collisions in the Response Authenticator *when Message-Authenticator isn't enforced*. The fix: require Message-Authenticator on all Access-Request/Accept/Reject/Challenge packets (or move to RadSec/DTLS).

**Q4. What concrete problems does RadSec solve over classic UDP RADIUS, and what happens to the shared secret?**
RadSec (RFC 6614, TCP 2083) puts RADIUS inside **TLS**: confidentiality for the whole packet (not just User-Password), HMAC/AEAD integrity (kills MD5 forgery), reliable ordered **TCP** transport (no Identifier exhaustion / lost-UDP retransmit guessing), and **mutual X.509 authentication** between RADIUS peers. The shared secret becomes the literal fixed string `"radsec"` — trust now derives from the certificates, not a static PSK. RADIUS/DTLS (RFC 7360, UDP 2083) is the datagram equivalent.

**Q5. Why can't you just run plain RADIUS over a VPN/IPsec tunnel to the cloud and skip RadSec?**
You can in narrow cases, but it doesn't scale or federate: you'd need a managed IPsec tunnel per site, the Identifier-exhaustion and UDP-reliability issues remain, and there's no per-peer certificate trust model. RadSec gives **per-NAS mutual-cert authentication and transport security end-to-end** with no separate tunnel orchestration — which is exactly why SecureW2 Cloud RADIUS standardizes on RadSec (often via a lightweight on-prem RadSec proxy for vendors lacking native support).

**Q6. Walk through eduroam routing for `student@home.edu` visiting another campus. Where are credentials verified?**
The visited AP sends the request to the **visited** RADIUS server, which parses the realm `home.edu` from the (outer) User-Name and **proxies** it — up to a national/top-level RADIUS server, then down to `home.edu`'s **home** server. Only the home server holds/validates the credentials (or the cert, inside the EAP tunnel). The visited site only ever sees Accept/Reject and the anonymous outer identity. Inter-federation hops run over RadSec.

**Q7. A certificate was just revoked but the user is still online. How do you boot them immediately, and what identifies the session?**
Send an RFC 5176 **Disconnect-Request (CoA Disconnect, UDP 3799)** to the NAS holding the session, identifying it via **Acct-Session-Id** and/or **Calling-Station-Id** (MAC) plus **NAS-IP-Address**. The NAS replies Disconnect-ACK and drops the port/association; the client re-authenticates and now fails because the cert is revoked (CRL/OCSP). This turns "revoked at next reauth" into "revoked in seconds." Use **CoA-Request** instead if you want to *re-policy* (e.g., quarantine VLAN) without a full disconnect.

**Q8. Why are RADIUS octet counters often wrong for big sessions, and how is it fixed?**
Acct-Input/Output-Octets are **32-bit**, wrapping at 4 GiB. RFC 2869 adds **Acct-Input-Gigawords / Acct-Output-Gigawords** (also 32-bit) as the high-order word; total bytes = `Gigawords * 2^32 + Octets`. Billing/usage code that ignores Gigawords undercounts heavy users massively.

**Q9. What's the difference between an Access-Challenge and an Access-Reject, and what role does the State attribute play?**
**Access-Challenge (11)** means "I need more from you" — it carries the next EAP-Request and a **State** attribute (an opaque cookie). The client must send a new Access-Request that **echoes the same State** so the server can correlate the multi-round-trip EAP conversation (EAP-TLS handshakes are many round trips). **Access-Reject (3)** is terminal "no." Losing/mismatching State mid-handshake breaks EAP and looks like a random auth failure.

---

➡ Next: [Day 15 — 802.1X Port-Based Access Control & the EAP Framework](day-15-8021x-eap-framework.md)
