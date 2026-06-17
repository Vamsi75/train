# Interview Rapid-Fire — 100 Q&A

Last-minute review. One or two sentences each. Read top to bottom.

## Crypto

**Q:** Symmetric vs asymmetric encryption?
**A:** Symmetric uses one shared key (fast, e.g. AES); asymmetric uses a public/private keypair (slow, e.g. RSA/ECC) for key exchange and signatures.

**Q:** Why do TLS handshakes use asymmetric crypto only briefly?
**A:** Asymmetric is expensive, so it authenticates and negotiates a symmetric session key, then bulk data uses fast symmetric ciphers.

**Q:** What does a hash function give you?
**A:** A fixed-length, one-way, collision-resistant digest used for integrity and signatures (e.g. SHA-256).

**Q:** Why is SHA-1 deprecated?
**A:** Practical collision attacks (SHAttered) make it unsafe for signatures; use SHA-256 or better.

**Q:** What is a digital signature?
**A:** A hash of the data encrypted with the signer's private key; verified with the public key to prove authenticity and integrity.

**Q:** RSA vs ECC?
**A:** ECC gives equivalent security at much smaller key sizes (P-256 ≈ RSA-3072), so it's faster with less overhead.

**Q:** What is forward secrecy?
**A:** Ephemeral key exchange (ECDHE/DHE) so that compromising a long-term key cannot decrypt past sessions.

**Q:** What is a nonce / IV?
**A:** A number used once / initialization vector that randomizes encryption so identical plaintext yields different ciphertext.

**Q:** What is HMAC?
**A:** A keyed hash providing integrity + authenticity of a message using a shared secret.

**Q:** What problem does a KDF solve?
**A:** It derives strong keys from weaker inputs (passwords, shared secrets), e.g. PBKDF2/HKDF, often with salt and iterations.

## X.509 & Encodings

**Q:** What is X.509?
**A:** The standard format for public-key certificates binding an identity (subject) to a public key, signed by a CA.

**Q:** Key fields in a cert?
**A:** Subject, Issuer, Serial, Validity (notBefore/notAfter), Public Key, SAN, Key Usage/EKU, and the CA signature.

**Q:** PEM vs DER?
**A:** DER is the raw binary ASN.1 encoding; PEM is Base64 DER wrapped in `-----BEGIN-----` headers.

**Q:** What is a SAN and why does it matter?
**A:** Subject Alternative Name lists the valid names (DNS, IP, UPN); modern clients ignore CN and require the name in the SAN.

**Q:** Difference between Key Usage and Extended Key Usage?
**A:** KeyUsage constrains the key's cryptographic operations (e.g. digitalSignature); EKU constrains purposes (serverAuth, clientAuth).

**Q:** What is a UPN SAN used for?
**A:** EAP-TLS maps a client cert to an AD account via the User Principal Name in an otherName SAN (OID 1.3.6.1.4.1.311.20.2.3).

**Q:** PKCS#10?
**A:** The Certificate Signing Request (CSR) format — a public key + subject info signed by the requester's private key.

**Q:** PKCS#12 / PFX?
**A:** A password-protected bundle containing a private key plus its certificate chain.

**Q:** PKCS#7 / P7B?
**A:** A container for certificates/CRLs (no private key), often used to ship a chain.

**Q:** PKCS#8?
**A:** The standard encoding for private keys (optionally encrypted), algorithm-agnostic.

## CA & Trust

**Q:** What is a CA?
**A:** A Certificate Authority that vouches for identities by signing certificates with its private key.

**Q:** Why a 2-tier (root + intermediate) hierarchy?
**A:** The root stays offline/air-gapped; the intermediate does daily issuance, so a compromised issuer can be revoked without replacing the root.

**Q:** What does pathlen do in basicConstraints?
**A:** It limits how many CAs can appear below this one; `pathlen:0` means it can only sign end-entity certs.

**Q:** What is cross-signing?
**A:** One CA signs another CA's certificate so clients trusting either root can build a valid chain.

**Q:** How does chain building work?
**A:** A client links leaf → intermediate(s) → a trusted root in its store, verifying each signature and constraints.

**Q:** What is a trust store?
**A:** The set of root CA certs a system/browser inherently trusts (e.g. Windows Root store, Mozilla bundle).

**Q:** Private vs public PKI?
**A:** Public CAs chain to roots in OS/browser stores; private/internal PKI requires distributing your own root to clients.

**Q:** What is name constraints?
**A:** A CA extension restricting which name spaces (e.g. domains) a sub-CA may issue for.

**Q:** What is a self-signed cert?
**A:** A cert where subject == issuer, signed by its own key; typical for root CAs or untrusted test certs.

**Q:** What is certificate pinning?
**A:** Hardcoding an expected cert/public key (SPKI hash) so a connection is rejected even if a rogue-but-valid cert is presented.

## Lifecycle & Revocation

**Q:** Stages of a certificate lifecycle?
**A:** Enrollment/issuance → distribution → validation/use → renewal/rekey → revocation/expiry.

**Q:** Renewal vs rekey?
**A:** Renewal extends validity (may keep the key); rekey issues a new keypair, which is more secure.

**Q:** What is a CRL?
**A:** A Certificate Revocation List — a signed, periodically published list of revoked serial numbers.

**Q:** Downside of CRLs?
**A:** They grow large and are only as fresh as the last publish interval, adding latency and staleness.

**Q:** What is OCSP?
**A:** Online Certificate Status Protocol — a real-time query to a responder for a single cert's status (good/revoked/unknown).

**Q:** What is OCSP stapling?
**A:** The server fetches and attaches a signed OCSP response in the TLS handshake, removing the client's separate lookup.

**Q:** What is OCSP must-staple?
**A:** A cert extension requiring a stapled OCSP response, so a missing staple fails the connection (closes soft-fail gaps).

**Q:** Common revocation reasons?
**A:** Key compromise, CA compromise, affiliation changed, superseded, cessation of operation.

**Q:** Why automate certificate management?
**A:** Short lifetimes (e.g. 90 days) and scale make manual renewal error-prone; ACME/SCEP/EST automate issuance and renewal.

**Q:** What is ACME?
**A:** The protocol (used by Let's Encrypt) for automated domain validation, issuance, and renewal of certs.

**Q:** What is SCEP / EST?
**A:** Enrollment protocols for devices; SCEP is the legacy MDM standard, EST is the modern TLS-based successor.

**Q:** What happens when a cert expires mid-session?
**A:** Established sessions usually continue; new handshakes fail validation until the cert is renewed.

## TLS

**Q:** What does TLS provide?
**A:** Confidentiality, integrity, and server (optionally client) authentication over a transport channel.

**Q:** TLS 1.2 vs 1.3 handshake?
**A:** 1.3 is faster (1-RTT, optional 0-RTT), removes legacy/static-RSA key exchange, and mandates forward secrecy.

**Q:** What is mutual TLS (mTLS)?
**A:** Both client and server present and validate certificates, authenticating each other.

**Q:** What is SNI?
**A:** Server Name Indication — the hostname sent in the ClientHello so a server picks the right cert for virtual hosts.

**Q:** What is a cipher suite?
**A:** A named combination of key exchange, authentication, bulk cipher, and MAC/PRF (e.g. ECDHE-RSA-AES128-GCM-SHA256).

**Q:** What is a session ticket / resumption?
**A:** A mechanism to resume a prior session without a full handshake, reducing latency.

**Q:** What's in the TLS Certificate message?
**A:** The end-entity cert and (ideally) its intermediate chain, so the peer can build trust to a root.

**Q:** Why send intermediates with the leaf?
**A:** Clients often lack intermediates; omitting them causes "incomplete chain" / untrusted errors.

**Q:** What TLS alert means untrusted CA?
**A:** `unknown_ca` (48) — the peer can't chain the presented cert to a trusted root.

**Q:** What is downgrade protection?
**A:** Mechanisms (e.g. TLS_FALLBACK_SCSV, version sentinels in 1.3) that detect an attacker forcing a weaker protocol.

## RADIUS & AAA

**Q:** What does RADIUS do?
**A:** Provides centralized Authentication, Authorization, and Accounting (AAA) for network access.

**Q:** RADIUS transport and ports?
**A:** UDP — 1812 for auth, 1813 for accounting (legacy 1645/1646).

**Q:** What is the shared secret?
**A:** A pre-shared key between NAS and RADIUS server used to authenticate packets and hash passwords; it is not transport encryption.

**Q:** Key RADIUS packet types?
**A:** Access-Request, Access-Challenge, Access-Accept, Access-Reject, plus Accounting-Request/Response.

**Q:** What is a NAS?
**A:** Network Access Server — the switch/AP/VPN that relays user credentials to the RADIUS server (the RADIUS client).

**Q:** What is the Message-Authenticator attribute?
**A:** An HMAC-MD5 over the packet that protects integrity; required for EAP and now recommended for all packets (Blast-RADIUS).

**Q:** What is an Access-Challenge for?
**A:** The server asks for more info (e.g. carrying EAP exchanges) before deciding accept/reject.

**Q:** RADIUS vs TACACS+?
**A:** RADIUS (UDP, combines authn+authz, encrypts only password) is for network access; TACACS+ (TCP, separates AAA, encrypts whole body) is for device admin.

**Q:** RADIUS vs Diameter?
**A:** Diameter is the reliable (TCP/SCTP), TLS-secured, extensible successor used in telecom; RADIUS persists in enterprise NAC.

**Q:** What are VSAs?
**A:** Vendor-Specific Attributes — vendor-defined RADIUS attributes (e.g. for VLAN/role assignment).

**Q:** How is dynamic VLAN assignment done?
**A:** Access-Accept returns Tunnel-Type, Tunnel-Medium-Type, and Tunnel-Private-Group-ID attributes naming the VLAN.

**Q:** What is CoA / Disconnect-Message?
**A:** RFC 5176 packets letting the server change authorization or kick a session after the fact (port 3799).

**Q:** What is a RADIUS proxy / realm?
**A:** A server forwarding requests by realm (`user@realm`) to a home server, enabling roaming and federation.

## 802.1X & EAP

**Q:** What is 802.1X?
**A:** A port-based network access control framework where a port stays blocked until the user authenticates.

**Q:** The three 802.1X roles?
**A:** Supplicant (client), Authenticator (switch/AP), Authentication Server (RADIUS).

**Q:** What is EAPOL?
**A:** EAP over LAN — the L2 encapsulation carrying EAP between supplicant and authenticator.

**Q:** How does EAP relate to RADIUS here?
**A:** The authenticator wraps EAP from EAPOL into RADIUS EAP-Message attributes and relays to the server (pass-through).

**Q:** What is EAP?
**A:** An authentication framework (not a method) that negotiates and runs one of many concrete methods.

**Q:** What is the EAP-Identity exchange?
**A:** The first request/response where the supplicant offers its (often anonymous) outer identity.

**Q:** What is identity privacy?
**A:** Using an anonymous outer identity (e.g. `anonymous@realm`) so the real username only appears inside the encrypted tunnel.

**Q:** What is MAB?
**A:** MAC Authentication Bypass — authenticating a device by its MAC when it can't do 802.1X (printers, IoT); weak, used as fallback.

**Q:** What ends a successful 802.1X exchange?
**A:** EAP-Success carried in an Access-Accept; the port opens (and keys are derived for wireless).

**Q:** What is the MSK?
**A:** The Master Session Key exported by EAP after TLS, sent to the AP to seed the 4-way handshake/PMK.

## EAP Methods

**Q:** What is EAP-TLS?
**A:** Mutual certificate-based EAP — both server and client present certs; strongest and passwordless.

**Q:** What is PEAP?
**A:** Protected EAP — a server-cert TLS tunnel protecting an inner method, usually MSCHAPv2 (password).

**Q:** What is EAP-TTLS?
**A:** A TLS tunnel (server cert) carrying inner methods including legacy PAP/CHAP; vendor-neutral alternative to PEAP.

**Q:** What is EAP-MSCHAPv2?
**A:** A challenge-response password method, almost always run inside PEAP/TTLS because it's weak on its own.

**Q:** What is EAP-FAST?
**A:** Cisco's tunneled method using a PAC instead of a server cert for the protected tunnel.

**Q:** What is TEAP?
**A:** Tunnel EAP (RFC 7170) supporting EAP chaining — authenticating user and machine in one session.

**Q:** EAP-TLS vs PEAP trade-off?
**A:** EAP-TLS needs a client-cert PKI but kills credential theft; PEAP is easier but exposes password-based inner auth.

**Q:** Why validate the server cert on the supplicant?
**A:** Without it, an evil-twin AP can present any cert and harvest PEAP-MSCHAPv2 credentials.

**Q:** What is the inner vs outer identity?
**A:** Outer is sent in the clear before the tunnel; inner is the real identity sent inside the encrypted TLS tunnel.

**Q:** What is EAP chaining?
**A:** Authenticating both machine and user identities in a single TEAP session for stronger posture decisions.

## WPA-Enterprise

**Q:** WPA2-Personal vs Enterprise?
**A:** Personal uses a shared PSK; Enterprise uses 802.1X/EAP with per-user RADIUS authentication.

**Q:** What is the PMK in Enterprise mode?
**A:** The Pairwise Master Key derived from the EAP MSK, feeding the 4-way handshake.

**Q:** What is the 4-way handshake?
**A:** The exchange that proves both sides hold the PMK and derives fresh per-session encryption keys (PTK).

**Q:** WPA2 vs WPA3-Enterprise?
**A:** WPA3-Enterprise adds stronger crypto (and a 192-bit suite using GCMP-256/EAP-TLS) and protected management frames.

**Q:** What is PMF (802.11w)?
**A:** Protected Management Frames — protects deauth/disassoc frames from spoofing; mandatory in WPA3.

**Q:** Why is per-user keying better than a PSK?
**A:** Each user gets unique session keys; revoking one user doesn't require re-keying everyone.

## Onboarding / IdP

**Q:** What is device onboarding?
**A:** Securely provisioning a device with its cert, network profile, and trust settings (often via a self-service portal).

**Q:** What is SCEP used for in onboarding?
**A:** Devices/MDM request and renew certificates automatically from a CA over SCEP.

**Q:** What role does an IdP play?
**A:** It authenticates the user (SAML/OIDC) before issuing/enrolling a certificate, binding identity to the cert.

**Q:** What is SAML vs OIDC?
**A:** Both are federated SSO; SAML is XML-based (enterprise), OIDC is JSON/OAuth2-based (modern apps/mobile).

**Q:** Why use cert-based auth over passwords for Wi-Fi?
**A:** Certs can't be phished or reused, eliminate password-change churn on the network, and support strong device binding.

**Q:** What is a network profile / .mobileconfig?
**A:** A packaged configuration (SSID, EAP type, CA trust, cert) pushed to a device so the user doesn't configure manually.

**Q:** How does dynamic policy use IdP attributes?
**A:** Group/role attributes from the IdP map to RADIUS VLAN/ACL assignments at authentication time.

## Architecture

**Q:** Where does the RADIUS server sit relative to AD?
**A:** It authenticates against the directory (LDAP/AD) or validates certs issued by a PKI tied to those identities.

**Q:** How do you make RADIUS highly available?
**A:** Multiple servers behind NAS failover lists or load balancing, with replicated config and shared/synced state.

**Q:** What is a cloud RADIUS / RADIUS-as-a-Service?
**A:** A managed, scalable RADIUS (e.g. SecureW2) integrating with cloud IdPs and a managed CA, removing on-prem servers.

**Q:** Why separate root CA offline?
**A:** To minimize attack surface — the most valuable key signs only intermediates, rarely, on an air-gapped system.

**Q:** What is an HSM and why use it?
**A:** A Hardware Security Module stores CA keys in tamper-resistant hardware so private keys never leave it.

**Q:** How does VLAN steering improve security?
**A:** Authenticated users land in role-appropriate segments, limiting lateral movement (microsegmentation).

## Security

**Q:** What is an evil-twin attack?
**A:** A rogue AP impersonating a legit SSID to trick supplicants into leaking credentials when server-cert validation is off.

**Q:** What is the Blast-RADIUS attack?
**A:** A 2024 MD5 chosen-prefix attack on RADIUS that lets an MITM forge Access-Accept; mitigated by mandatory Message-Authenticator / RADIUS-over-TLS.

**Q:** What is RadSec?
**A:** RADIUS over TLS/DTLS (RFC 6614/7360) that encrypts and authenticates the whole RADIUS exchange over TCP.

**Q:** Why is PEAP-MSCHAPv2 risky?
**A:** Its inner crypto is weak (DES-derived) and credentials are exposed if the server cert isn't strictly validated.

**Q:** What's the danger of accepting any server cert on a supplicant?
**A:** It defeats tunnel protection, enabling credential theft via a spoofed RADIUS/AP.

**Q:** How do you contain a CA key compromise?
**A:** Revoke the CA cert, distribute updated CRLs/trust, re-issue from a clean CA, and rotate affected leaf certs.

**Q:** What is certificate transparency (CT)?
**A:** Public append-only logs of issued certs so mis-issuance by public CAs is detectable.

**Q:** Why short-lived certificates?
**A:** They shrink the revocation window and blast radius of a key compromise, favoring rotation over revocation infrastructure.

**Q:** What is the principle of least privilege in PKI/NAC?
**A:** Grant each cert/role only the EKU, validity, and network access it needs — no wildcard trust or over-broad VLANs.

**Q:** First thing to check on an Access-Reject with no TLS in the trace?
**A:** Shared-secret mismatch or a missing/invalid Message-Authenticator between the NAS and the RADIUS server.
