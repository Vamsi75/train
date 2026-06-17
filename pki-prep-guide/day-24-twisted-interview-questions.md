# Day 24 — Twisted Interview Questions: Master Set

These are the questions that separate someone who has *read* about PKI and RADIUS from someone who has *run* it in production. Each answer is written the way you should say it out loud: confident, precise, no hand-waving. If you can answer 80% of these cold, you can hold your own in any PKI/network-access interview.

---

## Crypto & X.509

**Q. A certificate "contains" a public key but is "signed" by a private key. Whose keys are involved and where?**
Two different key pairs. The *subject's* public key is the payload being certified — it lives inside the TBSCertificate. The *issuer's* (CA's) private key signs the hash of that TBSCertificate, producing the signature appended at the end. The subject's private key never appears anywhere in the certificate; it stays on the subject's device/HSM. Verifying a cert means using the issuer's *public* key (from the issuer's cert) to check the signature — it has nothing to do with the subject's private key.

**Q. Why can't you just encrypt with the data you want to protect using the CA's private key — why hashing first?**
RSA signing is expensive and size-limited (you can only sign a block up to the modulus size). You hash the TBSCertificate to a fixed-length digest (e.g., SHA-256 = 32 bytes) and sign that. This also gives you the integrity property cleanly: any single-bit change to the cert changes the digest, breaking the signature. ECDSA/EdDSA work the same way conceptually — sign the digest, not the document.

**Q. What is the actual difference between encryption and signing with RSA, given both "use the key pair"?**
Encryption: sender uses the *recipient's public* key; only the recipient's *private* key decrypts → confidentiality. Signing: signer uses their *own private* key; anyone with the *public* key verifies → authenticity + integrity. They're inverse operations on the same math but solve opposite problems. Treating them as interchangeable (key reuse for both) is a real-world vulnerability and why X.509 has separate `keyEncipherment` and `digitalSignature` Key Usage bits.

**Q. SHA-1 is broken — does that mean every SHA-1 certificate is forgeable today?**
Not automatically. SHA-1 is broken for *collision resistance* (you can craft two inputs with the same hash), which threatens CA-signed certs because an attacker who influences cert content could engineer a collision. It is not (practically) broken for *second-preimage* yet. The real risk is a CA issuing a SHA-1 cert where an attacker controlled enough fields to pull off a chosen-prefix collision. That's why browsers hard-failed SHA-1 in the chain. Leaf self-signed SHA-1 with no attacker influence is weak but not instantly forgeable — but you still rip it out.

**Q. Why is ECDSA P-256 considered ~equivalent to RSA-3072, and why do we care?**
ECC's security scales with the curve size against the elliptic-curve discrete-log problem, which has no sub-exponential attack like RSA's integer factorization does. So you get RSA-3072-grade security in a 256-bit key. We care because smaller keys mean smaller certs, faster handshakes, less CPU on constrained devices (IoT, phones), and smaller EAP-TLS payloads — which directly affects 802.1X fragmentation (see RADIUS section).

**Q. What's in the X.509 SAN and why does it now matter more than the CN?**
Subject Alternative Name carries the actual identities a cert is valid for — DNS names, IP addresses, RFC822 email, UPN (via otherName), URIs. Modern TLS stacks (and Chrome since 58) ignore CN for hostname matching entirely and require the name in SAN. For client auth/EAP-TLS, the identity the RADIUS server keys off is typically a SAN entry (UPN or email), not the CN. CN is effectively a human-readable label now.

---

## CA Hierarchy & Trust

**Q. If the root CA never signs client or server certificates, why does it even exist — and why offline?**
The root's only job is to sign a small number of intermediate (issuing) CA certs and the occasional CRL. Its private key is the single most valuable secret in the entire PKI: compromise it and every cert ever issued under it is suspect, and you cannot revoke the root itself in any practical way (it's a trust anchor). So you keep it offline — air-gapped HSM, powered off in a safe — precisely *because* it touches so little. Low usage is what makes offline feasible. The intermediates do the high-volume day-to-day issuance and can be revoked by the root if compromised.

**Q. Why use an intermediate at all instead of issuing leaf certs straight from the root?**
Containment and operational sanity. If an issuing CA is compromised, you revoke that one intermediate at the root and stand up a new one — your trust anchor (the root) is untouched and still trusted by every device. You also get separation: different intermediates for different purposes (TLS server, user, device, smartcard) with different policies, key strengths, and lifetimes. Issuing from the root forces it online, which defeats the whole security model.

**Q. A device trusts Root A. You present a leaf chained to Intermediate B chained to Root A, but you only send the leaf. Does it work?**
Often "it depends," which is the trap. TLS servers should send leaf + all intermediates (not the root). If the server omits the intermediate, the client must build the chain itself — possible only if it has the intermediate cached or can fetch it via the leaf's Authority Information Access (AIA) caCertificate URL. Many clients (especially 802.1X supplicants and mobile) won't do AIA fetching, so you get intermittent, "works on my machine" failures. Rule: always bundle intermediates; never bundle the root.

**Q. Cross-signing — what problem does it solve?**
It lets one CA's certificate be vouched for by two different roots, so you can migrate trust without a flag day. Classic use: a new root isn't yet in old device trust stores, so you cross-sign the new intermediate with both the new root and an established old root. New devices chain to the new root; old devices chain via the cross-cert to the old root. Both validate. Let's Encrypt's ISRG Root X1 / IdenTrust DST Root CA X3 cross-sign is the textbook example.

**Q. What is path length constraint and what breaks if you set it wrong?**
`pathLenConstraint` in Basic Constraints caps how many CAs can appear *below* a given CA cert in a chain. `pathLen=0` means this CA can issue only end-entity certs, no sub-CAs. Set it too low and you can't later insert a policy/sub-CA layer without re-issuing. Leave it unconstrained on an intermediate and a compromised intermediate could mint its own sub-CAs. It's a structural control, not a runtime one — you can't change it without re-signing.

---

## Certificate Lifecycle & Revocation

**Q. Renewal vs rekey — what's the difference and when does each matter?**
Renewal = issue a new cert with a new validity window, *same key pair*. Rekey = generate a *new key pair* and a new cert. Renewal is cheaper and keeps the key continuity (useful where the key is pinned or bound to a TPM slot you don't want to disturb). Rekey is mandatory when the key may be compromised, when you're rotating per policy (key aging), when moving to a stronger algorithm, or when the old key was generated insecurely. Best practice for security-sensitive certs: rekey on every renewal so a slow key compromise has a bounded blast radius. "Renew" that silently reuses a leaked key is a trap.

**Q. What does the CA actually copy from a CSR, and what does it ignore?**
The CA copies the *public key* and proves the requester holds the matching private key (the CSR is self-signed — that's the proof of possession). Everything else — subject DN, SANs, validity, key usage, EKU — is *requested* but the CA is free to override or ignore based on its certificate template/profile. A well-run CA does NOT blindly trust the CSR's requested SANs; it derives identity from an authenticated enrollment context (AD account, SCEP challenge, device record). Treating the CSR's subject fields as authoritative is how you get mis-issuance.

**Q. Why does OCSP "soft-fail" undermine the entire point of revocation?**
Revocation only works if a "this cert is revoked" answer can *stop* the connection. Soft-fail means: if the client can't reach the OCSP responder (timeout, blocked, network captive portal), it proceeds as if the cert were good. An attacker who has stolen a key and gotten the cert revoked simply *blocks OCSP traffic* — trivial on a network they control — and the client soft-fails right into the MITM. So soft-fail turns revocation into a suggestion. The fixes: OCSP stapling (server presents a fresh signed status, no client→responder call), and OCSP Must-Staple (cert flag that makes a missing staple a hard error).

**Q. CRL vs OCSP — when is a CRL actually better?**
CRL is a signed list of revoked serials, fetched periodically and cached. It scales badly for huge populations (lists get megabytes) and has freshness lag (next-update window), but it's *offline-friendly* and privacy-preserving — the CA never learns which cert you're checking. OCSP is real-time and per-cert but leaks which cert a client is validating (privacy) and adds a live dependency. For internal device PKI where clients can cache and you control the population, CRL (or CRL Distribution Point + delta CRLs) is often more robust than depending on a live OCSP responder. OCSP stapling gets you the best of both.

**Q. A revoked cert still authenticates successfully on your Wi-Fi. Name three plausible causes.**
(1) The RADIUS server isn't checking revocation at all (no CRL/OCSP configured for client cert validation — very common). (2) It's using a stale cached CRL whose next-update hasn't passed, so the new revocation isn't seen yet. (3) OCSP soft-fail and the responder is unreachable. Bonus: the CDP/AIA URL in the cert is unreachable from the RADIUS server's network segment, so the check silently no-ops. The lesson: issuing revocation ≠ enforcement; you must verify the verifier.

**Q. Why is a short-lived certificate sometimes a *replacement* for revocation rather than a complement?**
If a cert lives 24 hours, the revocation window is at most 24 hours — often you just let it expire instead of running revocation infrastructure. This is the ACME / modern-PKI philosophy: automate issuance so aggressively that lifetimes shrink to where revocation latency stops mattering. The catch: it only works if renewal is fully automated and reliable, otherwise short lifetimes become a self-inflicted outage (see the hospital scenario on Day 25).

---

## TLS / mTLS

**Q. In a standard TLS 1.2 handshake, when is the session actually confidential, and what proves the server's identity?**
Identity is proven by the server's Certificate + its signature in the key exchange (e.g., ServerKeyExchange signed with the server's private key in ECDHE), which ties the ephemeral DH parameters to the certified key. Confidentiality kicks in after ChangeCipherSpec — the Finished messages are the first encrypted+authenticated messages, and they also verify that both sides computed the same handshake transcript (defeating tampering). The cert alone proves nothing without that signature step; a cert is public, anyone can copy it. Possession of the private key is what's actually demonstrated.

**Q. TLS 1.3 cut a round trip — how, and what did it remove that mattered for security?**
1.3 sends the client's key share in the ClientHello, so the server can derive keys and respond with everything encrypted in one round trip (1-RTT). It removed static-RSA key exchange (no forward secrecy), removed RSA key transport entirely in favor of (EC)DHE — so *every* 1.3 session has forward secrecy by design. It also encrypts most of the handshake after ServerHello, including the server certificate, improving privacy. The gotcha: 0-RTT early data is replayable, so it must not carry non-idempotent requests.

**Q. mTLS — what changes on the wire vs server-only TLS?**
The server sends a CertificateRequest, the client responds with its Certificate and a CertificateVerify (the client signs the handshake transcript with its private key — *that's* the proof of possession of the client key). Without CertificateVerify, a client cert is just a copied public document. mTLS = both sides do the cert + transcript-signature dance. EAP-TLS is essentially mTLS adapted to the EAP framing.

**Q. Why doesn't presenting a valid client certificate prove the client owns it?**
Because the certificate is public. The proof is the CertificateVerify message, where the client signs a hash of the entire handshake transcript with the private key. The server validates that signature with the public key in the cert. No valid signature → the client merely replayed someone's public cert and is rejected. Interviewers love this because juniors say "the cert proves identity" — the *signature over live, unpredictable handshake data* proves identity.

**Q. SNI is sent in the clear in TLS 1.2/1.3 — why, and what fixes it?**
The server needs to know which virtual host's certificate to present *before* it can encrypt anything, so SNI rides in the cleartext ClientHello. That leaks which site you're visiting even though the rest is encrypted. Encrypted Client Hello (ECH) fixes it by encrypting the inner ClientHello (including SNI) to a public key the server publishes via DNS, presenting only a generic outer SNI in clear.

---

## RADIUS & 802.1X

**Q. RADIUS uses UDP and a shared secret instead of TLS — what does the shared secret actually protect, and what does it leave exposed?**
The shared secret is used to (a) authenticate the Access-Request via the Request/Response Authenticator (so the NAS and server know they're talking to a legit peer) and (b) encrypt the User-Password attribute (MD5-based hiding) and protect Message-Authenticator. It does *not* encrypt the whole packet — most attributes (username, NAS info, VLAN assignments in the reply) travel in the clear. So an on-path attacker sees usernames and VLAN assignments. The MD5 construction is also weak. That's exactly why RadSec (RADIUS over TLS, TCP/2083) exists — it wraps the whole exchange in TLS.

**Q. Why is dynamic VLAN assignment delivered as three specific RADIUS *tunnel* attributes rather than a single "VLAN" attribute?**
Because RADIUS reuses the RFC 2868 tunneling attributes for VLAN assignment: `Tunnel-Type = VLAN (13)`, `Tunnel-Medium-Type = 802 (6)`, and `Tunnel-Private-Group-ID = <VLAN ID or name>`. All three must be present and consistent or the switch ignores the assignment and drops the user to the default/native VLAN. There's no dedicated "VLAN" attribute in base RADIUS — VLAN steering was bolted onto the tunnel-attribute framework, which is why a single missing or mistyped attribute silently fails.

**Q. Why does a large client certificate chain break 802.1X, and how do you fix it?**
EAP runs inside RADIUS, and a single RADIUS packet is limited (and the path may not handle large UDP/jumbo). EAP-TLS must fragment the client's certificate chain across many EAP-Request/Response round trips using EAP-TLS fragmentation. A big chain (multiple intermediates, RSA-4096 keys, fat certs) means many fragments → many round trips → and it stresses `Framed-MTU` / RADIUS proxy fragment handling. Symptoms: auth works on one NAS vendor and fails on another, or fails only for certain users. Fixes: shorten the chain (fewer intermediates), switch to ECC keys (smaller certs), don't ship the root in the client chain, raise `Framed-MTU`/fragment-size settings, and ensure every proxy in the path tolerates fragmentation. RadSec (TCP) sidesteps a lot of the UDP fragmentation pain.

**Q. What's the difference between authentication and authorization in a RADIUS Access-Accept, and where do people conflate them?**
Authentication = "are you who you claim" (the EAP exchange / credential check). Authorization = "what may you do" (the attributes in the Access-Accept: VLAN, ACL, session timeout, bandwidth). A single Access-Accept does both. People conflate them by thinking a valid cert = full access; in reality a valid cert can still be authorized into a quarantine VLAN based on posture/group. Identity ≠ entitlement.

**Q. CoA (Change of Authorization) — why does it exist and what's the failure mode people miss?**
CoA (RFC 5176) lets the RADIUS server push a mid-session change — re-authorize a user into a new VLAN, apply a new ACL, or Disconnect — without the user re-authenticating. It's how NAC quarantines a device after posture changes. The missed failure mode: CoA is a *separate* inbound packet to the NAS (UDP 3799) with its own shared secret and the NAS must accept it; firewalls, NAT, and "CoA disabled on the switch port" silently break it, so your quarantine action appears to succeed at the server but never lands on the device.

**Q. Why put a RADIUS proxy in the path at all?**
Realm-based routing (route `user@partner.com` to the partner's RADIUS), aggregation (one trust relationship to the cloud instead of N), protocol bridging (PEAP to a backend, RadSec to the cloud), policy/attribute rewriting, and resilience (load-balance/fail-over across home servers). Eduroam is the canonical proxy hierarchy. The cost: every proxy is a place where Message-Authenticator validation, fragment reassembly, and attribute filtering can go wrong.

---

## EAP Methods

**Q. Why is EAP-TLS immune to credential phishing but PEAP-MSCHAPv2 isn't?**
EAP-TLS authenticates with a *certificate and private key*. There is no shared secret to phish — the private key never leaves the device and is never transmitted, so a rogue AP / evil-twin RADIUS server gets nothing usable; it can't replay a private key it never saw. PEAP-MSCHAPv2 carries a password-derived MSCHAPv2 exchange inside the TLS tunnel. If the supplicant doesn't validate the server certificate (the default on many BYOD devices, or users click "trust"), an attacker stands up a rogue RADIUS server, the client builds a TLS tunnel *to the attacker*, and hands over the MSCHAPv2 challenge/response — which is offline-crackable to recover the password. The phishing vector is the password plus weak server-cert validation. No password, no phish.

**Q. Where in the EAP-TLS exchange does mutual authentication actually happen?**
Server-to-client auth: the server sends its certificate and signs the handshake (its key exchange / CertificateVerify in TLS 1.3), and the supplicant validates it against the configured trusted CA — *this* is what stops rogue RADIUS servers. Client-to-server auth: the supplicant sends its client certificate and a CertificateVerify signing the transcript with its private key; the RADIUS server validates the chain, checks revocation, and maps the identity. Mutual auth is only complete after *both* CertificateVerify steps succeed — not when certs are merely exchanged. A supplicant that doesn't validate the server cert has thrown away half the mutual auth.

**Q. PEAP vs EAP-TTLS — what's the real distinction?**
Both build a server-authenticated TLS tunnel then run an inner auth. PEAP (Microsoft/Cisco) typically runs EAP methods inside (EAP-MSCHAPv2, EAP-GTC) and is tightly tied to the Windows/AD world. EAP-TTLS (Funk) can run *legacy non-EAP* inner methods too (PAP, CHAP, MSCHAPv2) inside the tunnel, which makes it friendlier for backends that only speak PAP against an LDAP/token store. TTLS is more flexible on the inner method; PEAP is more ubiquitous on Windows. Both share PEAP's fatal flaw if server-cert validation is weak.

**Q. What does TEAP add that PEAP/TTLS lack, and why does it matter for device + user auth?**
TEAP (RFC 7170) supports *EAP chaining* — authenticating the machine AND the user in a single session inside one TLS tunnel, and binding the two together. That lets you enforce "this user, on this corporate machine" rather than "this user OR this machine," closing the gap where a valid user credential on a personal/unmanaged device gets full access. It also supports secure provisioning of credentials (PACs/certs). It's the modern answer to Windows machine+user auth done right.

**Q. Why is "Validate server certificate" the single most important supplicant setting in any tunneled EAP method?**
Because the entire security of PEAP/TTLS rests on the client refusing to build a tunnel with a server it can't verify. If validation is off (or the trusted-CA / server-name is unconstrained), any attacker with a RADIUS server and a rogue AP becomes a valid tunnel endpoint and harvests inner credentials. The setting must pin BOTH the trusted root CA *and* the expected RADIUS server name/SAN — pinning only the CA still lets any cert from that CA (or a public CA) impersonate the server. EAP-TLS is less sensitive only because there's no inner secret to steal, but you still validate the server to avoid rogue-server games.

---

## Onboarding & IdP

**Q. SCEP is "insecure" yet it's everywhere in MDM — reconcile that.**
SCEP's weakness is the shared challenge password: anyone with it can enroll, and it's often static, logged, or shipped in a profile. It also has weak proof-of-origin. But in an MDM context, the MDM has *already* authenticated and authorized the device (it pushed the profile to a managed, enrolled device), the SCEP challenge is dynamically generated per-device and short-lived, and the SCEP server only accepts requests proxied through the MDM/connector. So the MDM compensates for SCEP's protocol weaknesses with out-of-band device trust. SCEP alone on the open internet = bad; SCEP behind a dynamic-challenge MDM gateway = fine in practice. EST and ACME are the more modern, mutually authenticated successors.

**Q. EST vs SCEP — what does EST fix?**
EST (RFC 7030) runs over TLS (HTTPS) with proper mutual authentication options (TLS client cert, or HTTP auth), supports server-side key generation, standardized CA cert distribution (`/cacerts`), and re-enrollment with the existing cert. It removes SCEP's static-challenge weakness and the crufty PKCS#7-over-HTTP transport. If you're greenfield, EST or ACME over SCEP.

**Q. In SAML vs OIDC, what is each actually transporting, and which do you reach for in device onboarding?**
SAML transports XML assertions over browser redirects/POST — heavy, enterprise, SSO to web apps. OIDC sits on top of OAuth 2.0 and transports compact JWT ID tokens — lighter, API/mobile-friendly. For onboarding, you typically use either to authenticate the *user* to the onboarding portal (proving "this is alice in Okta/Entra"), then the portal triggers cert issuance bound to that verified identity. The IdP authenticates the human; the PKI then issues a credential the device uses thereafter — so the user authenticates once with a password and never needs it again.

**Q. Why does certificate-based onboarding *reduce* dependence on the IdP at auth time, and why is that good?**
After onboarding, the device authenticates to the network with EAP-TLS using its cert — the RADIUS server validates the cert/chain/revocation locally, no live call to the IdP per connection. That decouples daily network access from IdP availability and latency, removes the password from the wire entirely, and survives IdP outages. The IdP is consulted at *enrollment* time, not at every Wi-Fi association. This is the core "passwordless" value proposition.

**Q. A user leaves the company. With passwords you disable the AD account. With certs, what actually cuts off access?**
Revoking the user's client certificate (and ensuring the RADIUS server enforces revocation), or removing the user/cert from the authorization policy / device record. Disabling the AD account does NOT automatically stop EAP-TLS if the RADIUS server only validates the cert chain and not live directory status. So cert-based access requires a working revocation + de-provisioning path tied to the HR/IdP lifecycle, or an authorization lookup that checks AD group membership at auth time. This is a classic gotcha: "we disabled the account but they still got on Wi-Fi."

---

## Architecture / Design

**Q. Where do you terminate EAP-TLS — at the AP, the controller, or the RADIUS server — and why does it matter?**
At the RADIUS (AAA) server. The AP/controller is just the authenticator/NAS: it relays EAP frames between supplicant and RADIUS and enforces the resulting authorization (VLAN/ACL). The cert validation, chain building, revocation check, and identity mapping all happen on the RADIUS server because that's where the trust config and CA trust store live. The AP never sees inside the TLS tunnel. Putting trust decisions on the edge would mean distributing CA trust and revocation to every AP — an operational nightmare.

**Q. Design choice: one giant issuing CA vs multiple purpose-specific issuing CAs?**
Multiple, partitioned by purpose: user certs, device certs, server/TLS certs, maybe per-business-unit. Reasons: different templates/lifetimes/key policies, blast-radius containment (revoke/rebuild one CA without touching others), clearer audit, and the ability to scope which RADIUS servers/relying parties trust which issuer. The cost is more CRL/OCSP endpoints and more lifecycle automation. For anything beyond a small shop, partitioned issuing CAs under one offline root is the standard.

**Q. Your RADIUS server is a single point of failure for all network access. How do you design around it without splitting trust?**
Deploy at least two RADIUS servers (active/active) sharing the same trust config and CA trust store; configure every NAS with primary+secondary servers. Front them with RadSec or anycast/load-balancers if cloud. Keep policy in a shared store. The certs themselves are validated locally so there's no shared session state to replicate — any server can validate any cert independently. That statelessness is exactly why cert-based auth scales horizontally so well; password/token methods often need a shared backend.

**Q. How do you handle IoT devices that can't run a supplicant or hold a cert, on the same secure network?**
You don't force them into EAP-TLS. Segment them: MAB (MAC Authentication Bypass) with the MAC in an authorized list, dropped into a tightly ACL'd IoT VLAN with no lateral access; or pre-shared-key-per-device (PPSK/iPSK) where each device gets its own PSK mapped to a VLAN; or a separate SSID entirely. The architectural rule: never let an un-authenticatable device degrade the security of the certificate-authenticated population — isolate it. NAC posture + dynamic VLAN keeps them quarantined.

**Q. Cloud RADIUS vs on-prem — what genuinely changes in the threat and ops model?**
Cloud RADIUS removes you from patching/scaling the AAA tier and usually mandates RadSec (TLS) from your NAS to the cloud — which is a security *upgrade* over cleartext-attribute UDP RADIUS across your LAN. The trade: you now depend on WAN connectivity to the cloud for *every* auth (so you need RadSec proxies with local caching/failover, and ideally local survivability), and your trust config / CA integration lives off-prem. The crypto trust model is unchanged; the availability and data-residency model is what shifts.

---

## Security / Incident

**Q. An attacker stole a device's private key. The cert is still valid for 11 months. Walk through your response.**
(1) Revoke the cert immediately (CRL update + OCSP), confirm the RADIUS server *enforces* revocation and refreshes its CRL/OCSP cache. (2) De-provision the device in the IdP/MDM/authorization store so even a non-enforcing path drops it. (3) Rekey — issue a fresh cert with a new key pair on a known-good device; never reuse the compromised key. (4) Hunt: was the key extractable because it wasn't in a TPM/HSM? If so, fix the key-storage policy (non-exportable, hardware-bound). (5) Review whether session lifetimes / CoA can boot the device's existing active sessions. The key lesson: revocation must be both *issued* and *enforced*, and hardware-bound keys would have prevented extraction.

**Q. Why is crypto-agility an architectural property, not a config flag?**
Because swapping algorithms touches everything: CA signing algorithms, cert profiles, key sizes, supplicant/server cipher support, HSM firmware, protocol versions, and the *trust chains already deployed on millions of devices*. You can't flip a switch; you need the ability to run dual algorithms during migration (hybrid certs/cross-signing), automated re-issuance pipelines, and inventory of what's deployed. Organizations that hard-coded RSA-2048 everywhere with manual issuance have no agility — that's why PQC readiness is a design conversation now, not a 2030 patch.

**Q. Post-quantum: what specifically breaks, what survives, and what's the migration shape?**
Shor's algorithm breaks RSA and ECC (the public-key/signature and key-exchange layer) — so cert signatures and TLS key exchange are the exposure. Symmetric crypto (AES) and hashes (SHA-256/3) are only weakened by Grover's (effectively halved strength → use AES-256, SHA-384+), not broken. Migration shape: adopt NIST PQC standards (ML-KEM for key exchange, ML-DSA/SLH-DSA for signatures), deploy *hybrid* (classical + PQC) certs and key exchange so you're safe even if one scheme falls, and worry about "harvest now, decrypt later" for long-lived confidential data *today*. Long-lived CA roots should be the first to consider PQC because they outlive the threat horizon.

**Q. "Harvest now, decrypt later" — why does it change your priorities even before quantum computers exist?**
An adversary can record today's encrypted traffic and decrypt it once a cryptographically relevant quantum computer exists. So any data with a long confidentiality lifetime (medical records, state secrets, long-term contracts) is *already* at risk even though no quantum computer can break it yet. That justifies deploying PQC key exchange now for those flows, ahead of any signature migration, because confidentiality is retroactively breakable while authentication is not (you can't retroactively forge a past handshake's authenticity).

**Q. You see thousands of Access-Reject events for one user across many APs in minutes. Triage?**
First decide: credential/cert problem or infrastructure problem. Check the reject reason in the RADIUS logs — cert expired? chain/trust failure? revocation hit? identity-mapping failure? If it's one user on *every* AP simultaneously, it's almost certainly the user's cert (expired/revoked/clock skew) not the network. If it were many users on *one* AP, suspect that NAS/switch (shared secret mismatch, fragment handling, MTU). Cross-cut by NAS and by user to localize. Also check time sync — an expired-cert storm at a clock boundary is a classic mass event (see the hospital scenario).

**Q. Why is clock skew a security-relevant failure in PKI/EAP, not just a nuisance?**
Certificate validity (`notBefore`/`notAfter`), CRL/OCSP freshness windows, Kerberos tickets, and TLS handshake timestamps all depend on agreed time. A device with a wrong clock will reject a perfectly valid cert as "not yet valid" or "expired," or accept a cert that should be expired. At scale, NTP failure or a leap-second/timezone bug produces a synchronized auth outage that looks like an attack. Time is part of your trust infrastructure; treat NTP as security-critical.

**Q. What's the difference between a rogue AP and an evil-twin RADIUS server, and which does EAP-TLS stop?**
A rogue AP broadcasts your SSID to lure clients onto attacker-controlled radio. An evil-twin RADIUS server is the AAA backend the attacker stands up to accept the EAP exchange and harvest inner credentials. EAP-TLS defeats the *evil-twin RADIUS server* because the supplicant validates the server cert and there's no inner secret to steal even if it didn't — and it defeats the rogue AP's *credential theft* goal for the same reason. What EAP-TLS alone doesn't stop is the AP doing pure denial/jamming, or a user with a misconfigured supplicant that skips server validation. Server-cert validation on the supplicant is the linchpin.

---

➡ Next: [Day 25 — Mock Interview & Capstone](day-25-mock-interview-capstone.md)
