# Day 22 — Threats, Best Practices & Crypto-Agility

You've spent three weeks building, issuing, validating, and authenticating with certificates. Today we put on the attacker's hat. A PKI is a trust factory: everything downstream — TLS, EAP-TLS Wi-Fi, code signing, VPN — collapses if the factory is subverted. Understanding *how* PKIs get broken is what separates an operator from an architect. Then we look forward: crypto-agility and the post-quantum cliff that every PKI/CLM team will hit.

---

## THEORY

### 1. The PKI Threat Model — Think in Trust Anchors

A PKI's blast radius is defined by what trusts what. The single most important mental model:

> **Compromise the private key of a trust anchor, and you own everything that chains to it.**

Map the assets by *value of the key*:

| Asset | If compromised | Blast radius |
|-------|----------------|--------------|
| Root CA private key | Game over | Every cert in the hierarchy, retroactively and going forward |
| Intermediate / Issuing CA key | Forge any leaf under that issuer | All subscribers of that CA |
| RA (Registration Authority) | Authorize fraudulent issuance | Whatever the RA can request |
| OCSP/CRL signing key | Lie about revocation status | Revoked certs appear valid |
| Server/client leaf key | Impersonate one entity | One identity |

The asymmetry is brutal: a single root key may anchor millions of certs. That's *why* we obsess over root protection.

### 2. CA Key Compromise — The Worst Case

If an attacker extracts a CA's private key, they can mint certificates indistinguishable from legitimate ones. They are now a trusted CA. They can issue a cert for `login.yourbank.com`, sign it, and every client that trusts your root will accept it — TLS, EAP, everything.

There is **no clean recovery**. You cannot "rotate" a root the way you rotate a password:

- A trusted root is embedded in OS/browser trust stores, MDM profiles, supplicant configs, baked into firmware. Replacing it is a months-to-years migration.
- You must revoke the CA (but clients that don't check revocation, or that the attacker can MITM, won't notice) and distribute a new root everywhere.

**Defenses — why offline root + HSM:**

- **Offline root CA.** The root signs *only* intermediates, a handful of times a year, then goes back in a safe — air-gapped, powered off. An attacker on your network simply cannot reach it. Day-to-day issuance is delegated to **issuing CAs**, which are online but disposable: if an issuing CA is compromised, you revoke it from the (still-safe) root and stand up a new one. The damage is bounded.
- **HSM (Hardware Security Module).** The private key is generated *inside* tamper-resistant hardware (FIPS 140-2/140-3 Level 3+) and is **non-exportable** — the chip performs signing operations; the key never leaves in plaintext. Even root-level OS compromise can't exfiltrate the key. Use **M-of-N quorum** (e.g., 3-of-5 smartcards) to authorize root operations so no single insider can act alone.
- **Key ceremony.** Root generation is a scripted, witnessed, video-recorded event with split knowledge and dual control. Sounds theatrical; it's the audit backbone (WebTrust / CA/B Forum require it).

### 3. Mis-Issuance — When the CA Issues the Wrong Thing

The CA key isn't stolen, but the CA issues a cert it never should have. Two infamous cases every PKI engineer should know:

- **DigiNotar (2011).** Dutch CA breached; attacker issued **500+ fraudulent certs**, including a wildcard `*.google.com` used to MITM ~300,000 Iranian Gmail users. DigiNotar tried to hide it. When it surfaced, browsers **yanked the root entirely**. The CA was bankrupt within weeks. Lesson: **a CA that loses trust is dead** — the asset *is* trust.
- **Symantec distrust (2017–2018).** Not a single breach but a pattern: thousands of mis-issued/test certs, sloppy RA practices, sub-CAs operated without proper oversight. Google and Mozilla announced a phased **distrust of the entire Symantec CA chain**. Symantec sold its CA business to DigiCert, which had to re-issue customers onto new roots. Lesson: **systemic process failure can distrust even a giant**, and re-issuing the whole installed base is a logistical nightmare.

**Defenses:** strict domain validation, **CAA records** (DNS records that say which CAs may issue for a domain), Certificate Transparency (below), separation of RA and CA roles, automated linting (e.g., `zlint`, `certlint`) before issuance.

### 4. Weak Algorithms — Math That Aged Badly

Cryptography has a shelf life. Two canonical failures:

- **MD5 collision → rogue CA (2008).** Researchers (Sotirov et al.) exploited MD5 collisions to craft two certificates with the *same* MD5 hash: one a benign cert the CA would sign, the other a **CA certificate** with the basic-constraints CA bit set. The CA signed the benign one; the signature was equally valid on the malicious one. They got a working intermediate CA. Lesson: **the signature hash must be collision-resistant**, or anyone can manufacture trust. MD5 in certs is dead.
- **SHA-1 deprecation.** SHA-1 collisions went from theoretical to practical (SHAttered, 2017 — Google produced two PDFs with the same SHA-1). Browsers had already begun rejecting SHA-1 certs in 2016–2017. The migration was painful precisely because of the long tail of legacy devices.

**Gotchas:**
- Weak **RSA key sizes**: 1024-bit RSA is broken-ish for serious adversaries; **2048-bit is the floor, 3072/4096 for long-lived roots.**
- Bad randomness: the **Debian OpenSSL bug (2006–2008)** crippled the entropy pool, making keys guessable. **ROCA (2017)** — a flaw in Infineon's RSA key generation made keys factorable; millions of smartcards/TPMs affected.
- **Always pin to the signature algorithm, not just the key size.** A 4096-bit RSA key signed with MD5 is worthless.

### 5. RA / Validation Compromise

The **Registration Authority** decides *who* gets a cert. Subvert the RA or the domain-validation logic and you don't need the CA key — the CA will happily sign fraudulent requests for you.

- Web PKI examples: BGP hijacks or DNS poisoning to pass automated domain validation; exploiting validation methods that trust a single network vantage point. Defense: **multi-perspective validation** (validate from several network locations), DNSSEC, CAA.
- Enterprise: an over-permissive enrollment workflow where any authenticated user can request a cert with arbitrary SAN/UPN. **Misconfigured AD CS templates (ESC1–ESC8, Certified Pre-Owned research)** let low-priv users request certs that impersonate domain admins. Defense: lock down templates, restrict who can enroll, disable `EDITF_ATTRIBUTESUBJECTALTNAME2`.

### 6. Stolen Client Keys — Why On-Device Key Gen Matters

A client cert is only as trustworthy as the secrecy of its private key. If the key is stolen, the attacker *is* that user.

**The architecture choice that prevents this:**

- **Generate the key on the device, in hardware, and make it non-exportable.** TPM (Windows/laptops), Secure Enclave (Apple), Android Keystore/StrongBox. The device creates the keypair, the private key lives in hardware and **never leaves**, only the CSR/public key goes to the CA.
- Contrast with the bad pattern: CA generates the keypair and ships a **PFX/PKCS#12** file (key + cert) to the user by email/portal. That private key now exists as a file — copyable, emailable, exfiltratable, often protected by a weak password. One stolen PFX = one stolen identity, and you often can't tell it was copied.

This is core SecureW2 doctrine: **on-device, hardware-backed, non-exportable keys.** It turns "stolen credential" from a quiet copy into something that requires physically defeating the hardware. It's also why hardware-backed certs are strictly better than passwords — you can't phish a key that can't leave the chip.

### 7. Evil-Twin / Rogue RADIUS & PEAP Credential Theft

This is the network-auth attack that pays SecureW2's mortgage. Setup: attacker stands up a Wi-Fi AP with the **same SSID** as the corporate network ("evil twin") plus a **rogue RADIUS server**.

- With **PEAP-MSCHAPv2** (password-based EAP), the client's supplicant negotiates a TLS tunnel to the RADIUS server, then sends the **MSCHAPv2 challenge/response (a hash of the user's password)** inside it. If the client **doesn't validate the RADIUS server's certificate**, it happily tunnels to the *attacker's* server and hands over the MSCHAPv2 exchange. The attacker captures it and cracks it offline (tools like `asleap`, `hashcat`; MSCHAPv2 is effectively single-DES-strength). **Now the attacker has the user's AD password** — full domain credential theft from a parking lot.
- The "fix" for PEAP is to enforce **server certificate validation** on every client (validate the cert chain *and* pin the expected RADIUS server name). In practice, getting every BYOD/managed device configured correctly is fragile — one misconfigured supplicant leaks the org's password.

**The real fix: EAP-TLS.** There is no password to steal. The client authenticates with a **certificate + non-exportable private key**. Even if a user connects to the evil twin, the worst case is a failed mutual auth — there's no shared secret or password to capture. This is the security argument for cert-based Wi-Fi over PEAP, and it's why "passwordless network access" is the headline.

### 8. Downgrade Attacks

Adversary forces the weakest acceptable option:

- **TLS downgrade** (POODLE, FREAK, Logjam): MITM strips/forces older protocol versions or export-grade ciphers. Defense: disable SSLv3/TLS 1.0/1.1, disable export ciphers, **TLS 1.3** removes most downgrade surface; HSTS prevents HTTP downgrade.
- **EAP method downgrade / SSID confusion:** convince the supplicant to fall back to a weaker EAP method or a less-protected network. Defense: don't configure weak methods at all; lock the supplicant profile to EAP-TLS only.
- General principle: **a system is only as strong as its weakest enabled option.** Remove the weak options; don't merely "prefer" strong ones.

### 9. Certificate Transparency (CT) — Catching Mis-Issuance in the Web PKI

After DigiNotar, the web PKI needed a way to detect mis-issuance *publicly*. **Certificate Transparency** requires CAs to log every issued cert to public, append-only, cryptographically-verifiable **CT logs**. The CA gets a **Signed Certificate Timestamp (SCT)**; browsers (Chrome, Safari) **require SCTs** or they reject the cert.

Why it matters:
- A domain owner can **monitor** CT logs (crt.sh, Cert Spotter, internal monitors) and immediately see if *any* CA issued a cert for their domain that they didn't request — the canary for mis-issuance.
- It makes CA misbehavior *detectable after the fact* even if prevention fails. Detection is a control too.

**Scope gotcha:** CT is a **public web PKI** mechanism. Your **private/enterprise CA** (the one issuing EAP-TLS client certs) does **not** log to public CT — and shouldn't (you'd leak internal hostnames/usernames). The enterprise equivalent is your own issuance audit log + CLM platform reporting.

### 10. Best Practices — The Defensible PKI

1. **Key protection:** HSMs for all CA keys; hardware-backed, non-exportable keys for leaves; never email PFX files.
2. **Separation of duties:** distinct people/roles for CA admin, RA approval, audit. M-of-N for root operations.
3. **Least-privilege issuance:** tight cert templates, restricted EKUs, scoped SANs, restricted enrollers. A cert template is a security boundary.
4. **Short validity + automation:** short-lived certs limit the value of a stolen key and the pain of revocation (revocation is unreliable; expiry is certain). Short lifetimes *require* automation (ACME/SCEP/CLM) — the web PKI is moving toward **47-day TLS certs by 2029**.
5. **Monitoring / CT:** monitor public CT for your domains; monitor your internal issuance logs; alert on anomalies and impending expiries.
6. **Defense in depth:** CAA + multi-perspective validation + CT + revocation + network controls. No single layer is trusted to be perfect.
7. **Tested revocation + recovery runbooks:** know how you'd revoke an issuing CA and roll a new root *before* you need to.

### 11. Crypto-Agility — Assume Everything Rotates

**Crypto-agility** is the ability to change cryptographic algorithms, key sizes, and trust anchors **without re-architecting**. MD5→SHA-1→SHA-256 and SHA-1's death taught everyone that algorithms are perishable. Build for change:

- **Inventory everything.** You can't rotate what you can't find. Maintain a live inventory of every cert, key, algorithm, key size, and expiry (this is exactly what a CLM platform gives you).
- **Abstract crypto behind config**, not hardcoded algorithm choices. Support multiple algorithms simultaneously.
- **Automate issuance/renewal** so a mass re-issue is a campaign, not a catastrophe.
- **Practice rotation.** Rotate an issuing CA in a lab. Roll a server fleet to a new chain. Agility you've never exercised isn't agility.

### 12. Post-Quantum Cryptography (PQC) — The Coming Cliff

**The quantum threat.** A large, fault-tolerant quantum computer running **Shor's algorithm** breaks the math behind today's public-key crypto: it factors RSA and solves the discrete-log problem underlying **ECC/ECDSA/DH** in polynomial time. That means **RSA and ECC certificates, key exchange, and signatures all fall.** Symmetric crypto (AES) and hashes are only *weakened* (Grover's algorithm = quadratic speedup → double the key/hash size, e.g., AES-256, SHA-384), not broken.

**Harvest-now, decrypt-later (HNDL).** The threat is not just future — it's *today*. An adversary can record encrypted traffic now and decrypt it once quantum computers arrive. Anything that must stay confidential for 10–20 years (medical records, state secrets, long-lived keys) is **already at risk**. This is why "we'll deal with it when quantum computers exist" is the wrong answer.

**NIST PQC standards (finalized Aug 2024):**

| Standard | Algorithm (orig. name) | Purpose |
|----------|------------------------|---------|
| **FIPS 203 — ML-KEM** | CRYSTALS-Kyber | Key Encapsulation (key exchange / encryption) |
| **FIPS 204 — ML-DSA** | CRYSTALS-Dilithium | Digital Signatures (general-purpose) |
| **FIPS 205 — SLH-DSA** | SPHINCS+ | Hash-based signatures (stateless, conservative backup) |
| **FIPS 206 — FN-DSA** (draft) | FALCON | Compact lattice signatures |

These are **lattice-based** (ML-KEM/ML-DSA) and **hash-based** (SLH-DSA) — problems believed hard even for quantum computers. Note: PQC keys/signatures are **much larger** than RSA/ECC (ML-DSA signatures are kilobytes), which stresses cert sizes, EAP fragmentation (!), and embedded devices.

**Hybrid certificates / hybrid key exchange.** During the transition, you run **classical + PQC together** so you're safe if *either* holds. Examples: hybrid TLS key exchange (X25519 + ML-KEM — already shipping in Chrome/OpenSSL 3.5), and hybrid/composite certificates carrying both an ECDSA and an ML-DSA signature. Hedge against both "quantum arrives early" and "the new PQC algorithm has a flaw."

**What PKI/CLM teams should do NOW:**
1. **Build a cryptographic inventory** — find every RSA/ECC dependency, key size, and validity. (Crypto-agility prerequisite.)
2. **Prioritize by data lifetime** — protect long-confidentiality data against HNDL first (deploy hybrid key exchange).
3. **Demand crypto-agility from vendors** — HSMs, CLM, supplicants, NAC, RADIUS must have a PQC roadmap.
4. **Pilot hybrid TLS / hybrid certs** in a lab; measure the size/perf impact (handshake size, EAP fragmentation, embedded constraints).
5. **Watch the cert-size impact on EAP-TLS** — PQC certs are large; this collides directly with RADIUS/EAP fragmentation (Day 23). Plan MTU/RadSec accordingly.

---

## PRACTICE

### A. PKI Security Audit Checklist

**CA / Trust anchors**
- [ ] Root CA is **offline / air-gapped**, powered off between ceremonies.
- [ ] All CA keys in **HSM** (FIPS 140-2/3 L3+), non-exportable.
- [ ] Root operations require **M-of-N quorum**; ceremonies documented and witnessed.
- [ ] Issuing CAs are separate from root; revocation/rollover runbook exists and is tested.

**Issuance / RA**
- [ ] Cert templates least-privilege: restricted EKUs, scoped SANs/UPNs, restricted enrollers.
- [ ] AD CS hardened against ESC1–ESC8; `EDITF_ATTRIBUTESUBJECTALTNAME2` disabled.
- [ ] Separation of duties between CA admin, RA approver, auditor.
- [ ] Public domains have **CAA** records; web certs use multi-perspective validation.

**Algorithms / keys**
- [ ] No MD5/SHA-1 signatures anywhere. RSA ≥ 2048 (roots 3072/4096) or ECC P-256/P-384.
- [ ] Leaf keys **hardware-backed and non-exportable** (TPM/Secure Enclave/Keystore); **no PFX distribution**.
- [ ] Validity periods short; renewal automated (ACME/SCEP/CLM).

**Monitoring / revocation**
- [ ] Public **CT monitoring** for owned domains; internal issuance logs reviewed.
- [ ] CRL/OCSP reachable, fresh, and signed by a protected key; expiry alerting in place.

**Network auth (RADIUS/Wi-Fi)**
- [ ] **EAP-TLS** preferred; PEAP-MSCHAPv2 phased out.
- [ ] Server cert validation enforced on every supplicant (chain + name pinning).
- [ ] Weak EAP methods/TLS versions disabled (no downgrade path).

**Crypto-agility / PQC**
- [ ] Live cryptographic inventory exists.
- [ ] Vendors (HSM/CLM/RADIUS/supplicant) have a PQC roadmap.
- [ ] Hybrid key exchange piloted for long-confidentiality data.

### B. openssl — Check for Weak Keys/Algos/Expiry

```bash
# Inspect a cert: signature algorithm, key size, validity, SANs, EKU
openssl x509 -in cert.pem -noout -text | less

# Just the signature algorithm (flag MD5/SHA-1)
openssl x509 -in cert.pem -noout -text | grep -i "Signature Algorithm"

# Public key size (flag < 2048-bit RSA)
openssl x509 -in cert.pem -noout -text | grep -i "Public-Key"

# Expiry: dates + "is it valid for the next 30 days?"
openssl x509 -in cert.pem -noout -dates
openssl x509 -in cert.pem -noout -checkend 2592000   # exit 1 if expires within 30d

# Live server: full chain, protocol, cipher, and cert details
openssl s_client -connect host:443 -servername host -showcerts </dev/null \
  | openssl x509 -noout -text

# Refuse weak protocols when testing (should FAIL on a hardened server)
openssl s_client -connect host:443 -tls1_1 </dev/null      # expect failure
openssl s_client -connect host:443 -cipher 'EXPORT' </dev/null  # expect failure

# Verify a chain end-to-end (catches incomplete/wrong chains)
openssl verify -CAfile root.pem -untrusted intermediate.pem leaf.pem

# Detect a non-hardware key you can read = exportable = a smell
openssl rsa -in suspicious.key -check   # if this works without an HSM, the key is on disk
```

Batch expiry sweep (cron this):

```bash
for c in /etc/ssl/mycerts/*.pem; do
  if ! openssl x509 -in "$c" -noout -checkend 1209600 >/dev/null; then
    echo "EXPIRING within 14d: $c"
  fi
done
```

### C. "Is My Deployment Evil-Twin Resistant?" Checklist

- [ ] **Using EAP-TLS** (cert-based), not PEAP/TTLS with passwords. (Best answer — no secret to steal.)
- [ ] If any password-EAP remains: **server certificate validation is enforced** on every client.
- [ ] Clients pin the **expected RADIUS server name/identity**, not just "any trusted cert."
- [ ] Clients trust **only your private CA** for the RADIUS server cert — not a big public root that an attacker could buy a cert from.
- [ ] Supplicant profiles are **pushed by MDM/GPO**, locked, and users **cannot** click "trust" on an unknown server.
- [ ] No fallback to weaker EAP methods or open/legacy SSIDs.
- [ ] Client private keys are **hardware-backed, non-exportable**.
- [ ] Rogue-AP / WIPS detection deployed to spot evil twins on-site.

**Exercises:**
1. Pull the cert from any HTTPS site with `s_client` and report: signature algorithm, key type/size, validity window, and whether the chain verifies against your local trust store.
2. Find a SHA-1 or 1024-bit RSA cert in a lab (generate one with openssl) and write the one-paragraph "why this is unacceptable" you'd put in an audit finding.
3. Take a supplicant config (Windows Wi-Fi profile XML, or an Apple `.mobileconfig`) and identify exactly where server-cert validation and server-name pinning are set. Flip them off and explain, step by step, how an evil twin would harvest credentials with PEAP-MSCHAPv2.
4. Write a 5-line incident plan for "an issuing CA private key may be compromised." Who acts, what gets revoked, and how is a new chain distributed?
5. Estimate the EAP-TLS handshake size if leaf + intermediate certs switched to ML-DSA signatures. Would it exceed a single RADIUS packet? (Foreshadow Day 23 fragmentation.)

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why is an offline root CA worth the operational pain when an online HSM-protected root would also be hard to extract?**
Because defense in depth and blast radius. An HSM protects the *key material*, but an online root is still reachable: its issuance interface can be abused (mis-issuance without ever extracting the key), it's exposed to software vulns, and a compromised admin can sign things. An offline root removes the *network* and *availability* attack surface entirely — it physically can't be reached or abused day-to-day. You accept the pain of occasional ceremonies in exchange for the most valuable key in your organization being unreachable 364 days a year. HSM + offline are complementary, not alternatives.

**Q2. A stolen RSA private key for a leaf cert vs. revocation that "doesn't really work" — reconcile that.**
Revocation is best-effort: CRLs may be stale, OCSP may be soft-fail (clients proceed if the responder is unreachable), and an attacker MITM-ing the victim can also block the revocation check. So revoking a compromised leaf reduces but doesn't eliminate risk. The structural answer is to make leaf keys **non-exportable and hardware-backed** so they can't be quietly stolen in the first place, and to keep validity **short** so a stolen-but-undetected key expires fast. Revocation is the backstop; prevention + short lifetimes are the real controls.

**Q3. Walk me through the MD5 rogue-CA attack — why did a collision give the attacker a CA, not just a forged leaf?**
The CA signs the *hash* of the to-be-signed certificate (TBSCertificate). MD5 collisions let the researchers construct two different TBSCertificates with the **same MD5 hash**: one a benign cert the CA would willingly sign, the other crafted with `basicConstraints: CA=TRUE`. Because the hashes matched, the CA's signature over the benign cert was **equally valid** on the malicious CA cert. They got a legitimately-signed intermediate CA and could then issue anything. The takeaway: certificate security collapses to the **collision resistance of the signature hash** — break that and trust is forgeable.

**Q4. Your CISO says "we use PEAP-MSCHAPv2 and force server-cert validation, so we're fine — why migrate to EAP-TLS?"**
Server-cert validation *does* defeat the evil twin — *if every single client is configured correctly and stays that way*. The problem is operational fragility: one BYOD device, one user who clicks "trust," one MDM profile that didn't apply, and that device tunnels the MSCHAPv2 exchange to a rogue server, leaking a crackable hash of the user's **AD password**. The failure mode is silent and the prize is a domain credential. EAP-TLS removes the prize entirely: there's **no password** in the exchange — authentication is a cert with a non-exportable key. You go from "secure if 100% of clients are perfectly configured" to "secure by construction." That's why it's worth the migration.

**Q5. Why doesn't your enterprise EAP-TLS CA participate in Certificate Transparency, and what replaces it?**
CT is a **public web PKI** control: publicly-trusted CAs log to public append-only logs so domain owners and browsers can detect mis-issuance. Your private CA's certs contain internal hostnames, UPNs, device IDs — logging them publicly would be an **information-disclosure problem**, and browsers don't require SCTs for privately-trusted chains anyway. The enterprise equivalent is your **internal issuance audit trail + CLM reporting**: every issuance logged, reviewed, alertable, and tied to an identity. Same goal — detect anomalous issuance — different (private) mechanism.

**Q6. "Harvest now, decrypt later" — convince me to spend budget on PQC before a quantum computer exists.**
Because the attack window is retroactive. An adversary can record your encrypted traffic *today* and decrypt it the day a cryptographically-relevant quantum computer (running Shor's) arrives — breaking the RSA/ECC key exchange that protected it. So the real question isn't "when will quantum computers exist?" but "**how long must this data stay secret?**" If you have data that must remain confidential for 10–20 years and a quantum computer plausibly arrives in that window, your data is *already* exposed. Deploying **hybrid key exchange** (e.g., X25519 + ML-KEM) now closes the HNDL window for new traffic at minimal risk, since you're protected if *either* algorithm holds.

**Q7. How does post-quantum crypto collide with EAP-TLS and RADIUS specifically?**
PQC signatures and keys are **much larger** than RSA/ECC — ML-DSA signatures are kilobytes, and an X.509 chain with PQC signatures balloons. EAP-TLS already pushes a full cert chain through RADIUS, and RADIUS/UDP has long suffered **EAP fragmentation** problems (large frames fragmented across many RADIUS round-trips, MTU issues, packet loss). PQC certs make this dramatically worse — handshakes that used to fit in a few packets now span many more, increasing latency, fragmentation failures, and the chance of dropped auths. Mitigations: prune the chain, prefer compact PQC signature schemes (FN-DSA/FALCON), move to **RadSec (RADIUS over TLS/TCP)** which handles large payloads far better than UDP, and raise MTUs end to end. This is exactly why crypto-agility *and* transport modernization go together.

**Q8. What single architectural decision most reduces credential-theft risk across both Wi-Fi and TLS, and why?**
**Hardware-backed, non-exportable keys generated on-device**, combined with **certificate-based auth (EAP-TLS / mTLS)**. It simultaneously kills the two biggest credential-theft vectors: there's no password to phish or capture via evil twin, and there's no key file to copy or exfiltrate (the private key physically can't leave the TPM/Secure Enclave). You convert "credential theft" from a quiet copy operation into "physically defeat tamper-resistant hardware," which is out of reach for the overwhelming majority of attackers. Everything else — short validity, revocation, monitoring — is layered on top of that foundation.

➡ Next: [Day 23 — Real-Time Production Issues: Playbook](day-23-troubleshooting-production-playbook.md)
