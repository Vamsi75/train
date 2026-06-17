# Day 13 — AAA Model & RADIUS Fundamentals

> RADIUS is the protocol that turns "this device wants on the network" into a yes/no decision backed by an identity store. Every enterprise Wi-Fi login, every 802.1X switch port, every VPN, every SecureW2 Cloud RADIUS auth runs on the concepts in this file.

---

## THEORY

### 1. The AAA model — Authentication, Authorization, Accounting

AAA is the framework for controlling and logging network access. Keep the three A's crisp — interviewers will probe whether you can separate them:

| A | Question it answers | Example |
|---|---------------------|---------|
| **Authentication** | *Who are you?* | Verify a username/password, a client certificate (EAP-TLS), or a token. |
| **Authorization** | *What are you allowed to do / get?* | Put this user on VLAN 20, apply a downloadable ACL, set a session timeout, allow this VPN subnet. |
| **Accounting** | *What did you actually do, and for how long?* | Log session start/stop, bytes in/out, session duration — for billing, audit, and forensics. |

**Critical gotcha:** Authentication and Authorization are **not** the same. A correct certificate proves *who* you are (authN); it does not by itself decide *which VLAN* you land on (authZ). In RADIUS, the **Access-Accept** can carry both the "yes, you're authenticated" *and* the authorization attributes (VLAN, ACL, timeout) — but they are distinct concepts.

### 2. Where RADIUS fits

**RADIUS = Remote Authentication Dial-In User Service.** Born in 1991 (Livingston Enterprises) for dial-up modem pools — the name is a fossil. Today it is the dominant AAA protocol for:
- 802.1X port-based access control (wired switches + wireless APs).
- VPN concentrators.
- Network device admin login (though TACACS+ often wins here — see §8).

RADIUS is the **glue between an authenticator and an identity source**. The switch/AP has no idea how to validate a certificate or check a directory — it just forwards the request to the RADIUS server, which does the real work against an identity store and returns a verdict.

### 3. RFCs and history

| RFC | What it defines |
|-----|-----------------|
| **RFC 2865** | RADIUS — the core authentication/authorization protocol (obsoletes 2138). |
| **RFC 2866** | RADIUS Accounting. |
| RFC 2548 | Microsoft vendor-specific attributes (MS-MPPE keys used by EAP). |
| RFC 3579 | RADIUS support for EAP (how EAP rides inside RADIUS). |
| RFC 5176 | Dynamic Authorization (CoA / Disconnect — change a live session). |
| RFC 6614 | **RadSec** — RADIUS over TLS (the fix for RADIUS's transport weaknesses; covered Day 14). |

### 4. The players

```text
 [ Supplicant ]        [ Authenticator / NAS ]       [ RADIUS / AAA server ]      [ Identity store ]
  laptop, phone   --->   switch port / Wi-Fi AP  --->     FreeRADIUS /        --->  AD / LDAP / SQL /
  (802.1X client)  802.1X    (the "RADIUS client")  RADIUS  SecureW2 Cloud RADIUS      cert validation
                    EAPOL                            (UDP)
```

- **Supplicant** — the end device's 802.1X software (Windows native, wpa_supplicant, macOS, etc.). It speaks **EAPOL** (EAP over LAN) to the authenticator. It does **not** speak RADIUS.
- **Authenticator / NAS (Network Access Server)** — the switch or wireless controller/AP. It is the **RADIUS client**. It relays EAP between supplicant and server but never sees the credential's secret in EAP-TLS. It controls the physical/logical port: blocked until the server says "accept."
- **RADIUS / AAA server** — the brain. Validates credentials, applies policy, returns accept/reject + attributes. Examples: FreeRADIUS, Microsoft NPS, Cisco ISE, **SecureW2 Cloud RADIUS**.
- **Identity store / backend** — AD, LDAP, a SQL database, or (for EAP-TLS) the PKI trust chain used to validate the client certificate. The RADIUS server queries this; it is not itself the store.

**Terminology trap:** the "RADIUS client" is the **NAS (switch/AP)**, *not* the end-user laptop. The laptop is the supplicant. Getting this backwards is a classic interview stumble.

### 5. Transport: UDP and the ports

RADIUS runs over **UDP**, not TCP. (RadSec later moves it to TCP/TLS.)

| Purpose | Modern port (RFC) | Legacy port |
|---------|-------------------|-------------|
| Authentication / Authorization | **UDP 1812** | UDP 1645 |
| Accounting | **UDP 1813** | UDP 1646 |

The legacy 1645/1646 ports conflicted with the "datametrics" service and were corrected to 1812/1813 by IANA. Many vendors still default to or accept the legacy pair, so you'll see both in the wild. Reliability (retransmit on no response) is the NAS's job since UDP gives no delivery guarantee.

### 6. The shared secret, packet authenticators, and password hiding

RADIUS has **no per-packet encryption**. Instead, the NAS and the RADIUS server are preconfigured with a **shared secret** (a password string). The secret is used three ways:

1. **Request Authenticator** — in an Access-Request, this is a 16-byte random nonce.
2. **Response Authenticator** — in Access-Accept/Reject/Challenge, the server computes:
   `MD5(Code + ID + Length + RequestAuthenticator + Attributes + SharedSecret)`.
   The NAS recomputes it; if it matches, the response is genuine. This is how RADIUS "authenticates" packets and prevents response spoofing.
3. **Password hiding** — the `User-Password` attribute is XORed with a stream derived from `MD5(SharedSecret + RequestAuthenticator)`. It is **obfuscated, not encrypted**.

**Why this is weak (say this in an interview):**
- Only `User-Password` is hidden; **all other attributes are cleartext** on the wire (username, VLAN, Calling-Station-Id/MAC, etc.).
- The construction relies on **MD5**, which is cryptographically broken.
- A weak/shared/reused shared secret is the whole security model — and many deployments use the same weak secret everywhere.
- This is exactly why **RadSec (RADIUS over TLS, Day 14)** exists: wrap the whole conversation in TLS and the cleartext/MD5 problems vanish.

> Note: For EAP methods like EAP-TLS, the *credential* is protected by the EAP/TLS tunnel itself, so the user's secret isn't exposed even over plain RADIUS. But the surrounding RADIUS attributes still are. RadSec protects everything.

### 7. Packet types and the basic conversation

The four RADIUS codes you must know cold:

| Code | Name | Meaning |
|------|------|---------|
| 1 | **Access-Request** | NAS → server: "here are credentials, may this user in?" |
| 2 | **Access-Accept** | Server → NAS: "yes" (+ authorization attributes). |
| 3 | **Access-Reject** | Server → NAS: "no." |
| 11 | **Access-Challenge** | Server → NAS: "I need more info / continue the EAP exchange." |

(Accounting uses codes 4 `Accounting-Request` / 5 `Accounting-Response`.)

The **Access-Challenge** is the engine of multi-step auth. EAP-TLS is *many* round trips — every fragment of the TLS handshake comes back from the server as an Access-Challenge, the NAS forwards it to the supplicant, and the supplicant's reply comes back in a new Access-Request. The loop repeats until the server issues a final Access-Accept (with the derived MPPE session keys) or Access-Reject.

```text
Simple PAP/CHAP auth (one round trip):
  NAS  --- Access-Request (User-Name, User-Password) --->  RADIUS
  NAS  <-- Access-Accept  (Framed-VLAN, Session-Timeout) -- RADIUS

EAP-TLS (many round trips, simplified):
  NAS  --- Access-Request (EAP: ClientHello fragment) --->  RADIUS
  NAS  <-- Access-Challenge (EAP: ServerHello, Cert...) --  RADIUS
  NAS  --- Access-Request (EAP: client Cert, CertVerify) -> RADIUS
  ...   (repeat until handshake done) ...
  NAS  <-- Access-Accept (EAP-Success, MS-MPPE keys) ----  RADIUS
```

### 8. RADIUS vs TACACS+ vs DIAMETER

| Feature | **RADIUS** | **TACACS+** | **DIAMETER** |
|---------|-----------|-------------|--------------|
| Origin | IETF (RFC 2865) | Cisco | IETF (successor to RADIUS, RFC 6733) |
| Transport | UDP (1812/1813) | **TCP 49** | TCP/SCTP, **TLS/IPsec** |
| Encryption | Only password obfuscated (MD5) | **Entire payload encrypted** | TLS/IPsec — full protection |
| AAA separation | AuthN & AuthZ combined in one exchange | **AuthN / AuthZ / Acct fully separated** | Separated, extensible |
| Primary use | **Network access** (Wi-Fi, 802.1X, VPN) | **Device admin** (per-command authZ on routers/switches) | Telco / 4G-5G (mobile core), IMS |
| Reliability | App-level retransmit over UDP | TCP-reliable | Reliable + failover, peer state |

Quick mental model:
- **RADIUS** = "let users onto the network." Lightweight, ubiquitous.
- **TACACS+** = "control what admins can type on network gear." Per-command authorization, full payload encryption.
- **DIAMETER** = "RADIUS done right for carriers." More capable, far heavier; you rarely meet it outside telco.

### 9. RADIUS as the glue — and Cloud RADIUS / SecureW2

The whole value of RADIUS is **decoupling**: the authenticator (any switch/AP from any vendor) speaks a standard protocol, and the RADIUS server adapts that to whatever identity source you have. Swap AD for Azure/Entra, or move auth to certificates, and the switches never change.

**Cloud RADIUS** (SecureW2's model) takes the RADIUS server out of the data center and runs it as a managed, geo-redundant service:
- The RADIUS server **terminates EAP-TLS** (it's the TLS server side from Day 12) and validates the client certificate against the managed PKI — no passwords, no AD password exposure.
- Authorization policies (VLAN assignment, dynamic VLAN/role) come back in the Access-Accept.
- It integrates with cloud identity (Entra ID, Google, Okta) for issuing those certs and for policy lookups.
- RadSec (Day 14) secures the link between on-prem APs and the cloud RADIUS service over the internet.

So everything in this file — the players, Access-Request/Challenge/Accept loop, shared secret, EAP-over-RADIUS — is exactly what's happening under the hood when a device joins a SecureW2-secured network.

---

## PRACTICE

> We'll use **FreeRADIUS** (the reference open-source RADIUS server) and its test clients `radtest`/`radclient`. Commands assume Linux (or WSL). On Windows, run inside WSL/Ubuntu or a container.

### Install FreeRADIUS

```bash
# Debian / Ubuntu
sudo apt-get update
sudo apt-get install -y freeradius freeradius-utils

# RHEL / Fedora
# sudo dnf install -y freeradius freeradius-utils

freeradius -v          # confirm version
```

### Define a test user and a client (NAS)

```bash
# 1) Add a test user to the 'users' file (authorize file in v3).
#    Path is typically /etc/freeradius/3.0/users  (or .../mods-config/files/authorize)
sudo tee -a /etc/freeradius/3.0/users >/dev/null <<'EOF'
# username   auth check                 reply attributes (authorization)
alice  Cleartext-Password := "S3cret!"
       Reply-Message := "Welcome alice",
       Tunnel-Type := VLAN,
       Tunnel-Medium-Type := IEEE-802,
       Tunnel-Private-Group-Id := "20"
EOF

# 2) Authorize a RADIUS client (the NAS) with a shared secret.
#    Edit /etc/freeradius/3.0/clients.conf
sudo tee -a /etc/freeradius/3.0/clients.conf >/dev/null <<'EOF'
client localhost-test {
    ipaddr = 127.0.0.1
    secret = testing123
}
EOF
```

### Run the server in debug mode (the single most useful RADIUS skill)

```bash
# Stop the service, then run in the foreground with full debug (-X).
sudo systemctl stop freeradius
sudo freeradius -X        # watch EVERY packet, attribute, and policy decision live
#   Leave this running in one terminal. -X is how you debug 99% of RADIUS issues.
```

### Test with radtest (simple) and radclient (precise)

```bash
# radtest <user> <password> <server[:port]> <nas-port> <shared-secret>
radtest alice 'S3cret!' 127.0.0.1:1812 0 testing123
#   Expect: "Received Access-Accept" + the VLAN/Reply-Message attributes.

# Wrong password -> Access-Reject (watch it in the -X window too)
radtest alice 'WrongPass' 127.0.0.1:1812 0 testing123

# radclient gives byte-level control. Feed attributes on stdin.
echo "User-Name=alice,User-Password=S3cret!" | \
  radclient -x 127.0.0.1:1812 auth testing123
#   -x = verbose; shows the Access-Request you sent and the Access-Accept returned.
```

### Send an Accounting packet (RFC 2866) to port 1813

```bash
echo "User-Name=alice,Acct-Status-Type=Start,Acct-Session-Id=abc123" | \
  radclient -x 127.0.0.1:1813 acct testing123
#   Expect: Accounting-Response. Note this hits 1813, not 1812.
```

### Inspect the conversation on the wire

```bash
# See the cleartext attributes (and the obfuscated User-Password) for yourself.
sudo tcpdump -i lo -n -vv udp port 1812 or udp port 1813
#   Note: User-Name, NAS attributes, VLAN reply -> all CLEARTEXT.
#   Only User-Password is obfuscated. This is the weakness RadSec fixes.
```

### Read / understand the users file

```bash
# The 'users' file format: first line = match + check items (the password to verify);
# indented following lines = reply items (authorization sent in Access-Accept).
# 'DEFAULT' entries act as fall-through rules. Order matters; first match wins
# unless 'Fall-Through = Yes' is set.
sudo sed -n '1,40p' /etc/freeradius/3.0/users
```

**Exercises:**
1. Run `freeradius -X`, then `radtest` a valid and an invalid password. In the debug output, find the exact line where the server decides Accept vs Reject and identify which module made the decision.
2. In the `-X` output of a successful auth, locate the `Tunnel-Private-Group-Id` (VLAN 20) being sent back. Explain which "A" of AAA that attribute represents and why it is *not* authentication.
3. Run the `tcpdump` capture during a `radtest`. Confirm `User-Name` is cleartext and `User-Password` is not. Write one sentence on why this argues for RadSec.
4. Send a Start and then a Stop accounting packet (`Acct-Status-Type=Stop`, add `Acct-Session-Time=120`) with `radclient` to 1813. Confirm both get `Accounting-Response`.
5. Add a `DEFAULT` reject rule to the users file and a second user that matches a specific entry first. Demonstrate "first match wins" and `Fall-Through`.
6. **Concept check:** Without running anything, write down which device is the *RADIUS client* in an enterprise Wi-Fi login, and which is the *supplicant*. Then state where the shared secret lives.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Distinguish Authentication from Authorization in a single RADIUS exchange.**
Authentication is the server verifying *who* the user is (password check, certificate validation). Authorization is *what* the user gets — VLAN, ACL, session timeout — returned as attributes. Both can ride in one **Access-Accept**, but they're separate concepts: a valid cert proves identity (authN); the `Tunnel-Private-Group-Id` attribute placing you on VLAN 20 is authZ.

**Q2. Who is the "RADIUS client" — the laptop or the switch?**
The **switch/AP (the NAS)** is the RADIUS client; it holds the shared secret and sends Access-Requests. The laptop is the **supplicant** and speaks **EAPOL** to the NAS, never RADIUS. Confusing the two is the most common RADIUS misconception.

**Q3. RADIUS uses UDP and no full encryption — how does it stop an attacker from spoofing an Access-Accept?**
The **Response Authenticator**: the server hashes `MD5(Code+ID+Length+RequestAuthenticator+Attributes+SharedSecret)`. The NAS recomputes it and rejects any response whose authenticator doesn't match. Without the shared secret an attacker can't forge a valid Accept. (It's still MD5-based and only the password is hidden — hence RadSec.)

**Q4. Is the `User-Password` attribute encrypted?**
No — it's **obfuscated**, XORed with a keystream derived from `MD5(SharedSecret + RequestAuthenticator)`. It's reversible by anyone holding the shared secret, uses broken MD5, and **every other attribute (username, MAC, VLAN) is plain cleartext**. This is a deliberate point to raise when justifying RadSec.

**Q5. Why does EAP-TLS produce so many RADIUS packets, and what packet type drives the loop?**
EAP-TLS is a full mutual-TLS handshake fragmented into EAP messages; each leg of the handshake is one round trip. The server keeps the exchange going with **Access-Challenge** packets — the NAS relays each challenge to the supplicant and returns the reply in a new Access-Request — until the handshake completes with a final **Access-Accept** (carrying MS-MPPE keys) or **Access-Reject**.

**Q6. When would you choose TACACS+ over RADIUS?**
For **network device administration** where you need per-command authorization and full payload encryption — e.g., controlling exactly which CLI commands an admin may run on routers/switches and logging each one. TACACS+ separates AuthN/AuthZ/Acct and encrypts the whole packet over TCP/49. RADIUS combines AuthN+AuthZ and is aimed at network *access* (Wi-Fi/802.1X/VPN), not device admin.

**Q7. Which ports does RADIUS use, and why do you sometimes see 1645/1646?**
**1812** (auth) and **1813** (accounting) are the IANA-assigned modern ports. **1645/1646** are the legacy ports from RADIUS's early days; they clashed with another registered service and were corrected. Many vendors still default to or accept the legacy pair, so both appear in real deployments — always confirm which the NAS is configured for.

**Q8. The shared secret is correct but auth fails for one NAS only. What do you check?**
Confirm the NAS's source IP matches the `client {}` definition on the server (NAT/secondary interface mismatches break the client lookup), that the secret is byte-identical on both ends (trailing spaces!), and that the request reaches the right port (1812 vs legacy 1645). Run `freeradius -X` — if the server logs "Ignoring request ... unknown client," it's an IP/client mismatch, not a credential problem.

**Q9. How does SecureW2 Cloud RADIUS change the classic on-prem RADIUS picture?**
It runs the RADIUS server as a managed cloud service that **terminates EAP-TLS** (validating device/user certificates from a managed PKI instead of passwords), returns authorization like dynamic VLANs in the Access-Accept, and integrates with cloud IdPs (Entra/Google/Okta). The on-prem APs reach it via **RadSec** (RADIUS over TLS), eliminating the cleartext/MD5 exposure of plain RADIUS over the internet.

---

➡ Next: [Day 14 — RADIUS Deep Attributes, RadSec & Proxy](day-14-radius-deep-attributes-radsec-proxy.md)
