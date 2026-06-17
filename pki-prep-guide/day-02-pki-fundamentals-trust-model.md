# Day 02 — PKI Fundamentals & the Trust Model

> Day 01 gave us key pairs and signatures. But a public key on its own is just bytes — how do you know it belongs to `login.securew2.com` and not an attacker? PKI is the system that answers exactly that question: **binding an identity to a public key in a way third parties can trust without ever meeting the subject.**

## THEORY

### 1. The Problem PKI Actually Solves

Asymmetric crypto lets anyone verify a signature with a public key. But that only proves "whoever holds the matching private key signed this" — it says **nothing about *who* that is.** This is the **key-distribution / identity-binding problem**.

- If you just hand out public keys, an attacker can hand out *their* key claiming to be the bank/Wi-Fi/server. Verification succeeds — against the wrong key.
- A naive fix: pre-share every public key with everyone. Doesn't scale (n² problem) and breaks the moment a new party appears.

**PKI's answer:** a small number of mutually trusted authorities (**CAs**) vouch for the binding. A CA digitally signs a statement: *"this public key belongs to this identity, valid for this period, for these uses."* That signed statement is an **X.509 certificate**. Now anyone who trusts the CA can verify any identity the CA has vouched for — collapsing the n² trust problem to "trust a handful of roots."

> The certificate is not secret. It's public. Its value is entirely in the CA's signature over the identity↔key binding.

### 2. Core PKI Components

| Component | Role | Real-world example |
|-----------|------|--------------------|
| **CA (Certificate Authority)** | Issues and signs certificates; the trust anchor. Operates roots and issuing/intermediate CAs. | DigiCert, Let's Encrypt; SecureW2 **Cloud PKI** managed CA |
| **RA (Registration Authority)** | Verifies the *identity* of a requester before the CA issues. Authentication/authorization gate. | SecureW2 onboarding portal authenticating to IdP/SAML before issuing a device cert |
| **VA (Validation Authority)** | Answers "is this cert still valid right now?" via CRL/OCSP. | OCSP responder |
| **Subscriber / End Entity** | The subject the cert is issued to (a server, user, or device). | A laptop with an EAP-TLS client cert |
| **Relying Party** | Anyone who *verifies* and *trusts* a cert. | The RADIUS server validating a client cert; a browser |
| **Repository** | Where certs, CRLs, and policy docs are published. | AIA/CDP URLs, LDAP, directory |

A subtle but exam-worthy point: the **RA does the identity vetting; the CA does the cryptographic signing.** In cloud PKI these are often the same product, but the *roles* are distinct. SecureW2's value is largely a slick RA — it ties cert issuance to your existing IdP (Azure AD/Entra, Okta, Google) so a user proves who they are *once*, then gets a device cert for passwordless Wi-Fi.

### 3. The Chain of Trust & Trust Anchors

Certificates form a **chain** ending at a self-signed **root**.

```
[Root CA]            <- self-signed; trust anchor; lives in the trust store
   └─ signs
[Intermediate CA]    <- "issuing CA"; signed by root; does day-to-day issuance
        └─ signs
[End-entity cert]    <- server/user/device; the leaf
```

Verification (relying party's job) walks **bottom-up**:
1. Leaf's signature is verified using the intermediate's public key.
2. Intermediate's signature is verified using the root's public key.
3. The root is checked against the **local trust store** (it must be present and trusted — its self-signature is *not* what makes it trustworthy; its presence in the store is).
4. At each step: validity dates, BasicConstraints (`CA:TRUE`), KeyUsage/EKU, name constraints, and revocation are checked.

**Why intermediates exist (don't sign leaves directly with the root):**
- The root's private key can stay **offline in an HSM**, powered on rarely. If an issuing CA is compromised, you revoke *that intermediate*, not the irreplaceable root.
- Roots have 20+ year lifetimes and are baked into millions of devices; you cannot easily rotate them. Intermediates are disposable by comparison.

> **Gotcha — "incomplete chain":** the leaf cert validates fine in your testing because your machine happens to cache the intermediate, but other clients fail. Servers must send the **full chain except the root** (the leaf + intermediates). The root is supplied by the client's trust store, not the server.

### 4. Trust Stores (OS / Browser)

The **trust store** (a.k.a. root store) is the curated list of root CA certificates a platform trusts by default.

- **Windows:** Certificate Store (`certmgr.msc` / `certlm.msc`), managed via the Microsoft Trusted Root Program; viewable under "Trusted Root Certification Authorities."
- **macOS / iOS:** Keychain Access / Apple Trust Store.
- **Linux:** `/etc/ssl/certs`, `/etc/pki/tls/certs`, `ca-certificates` package.
- **Browsers:** Mozilla maintains its own store (NSS); Chrome now ships the **Chrome Root Store**; Apple/MS use the OS store.

Implications:
- A cert chaining to a root **not** in the relying party's store is "untrusted" — regardless of cryptographic validity. This is the #1 cause of "your connection is not private."
- **Enterprise/private PKI must distribute its root** to every endpoint (via GPO/MDM/Intune/Jamf). For EAP-TLS Wi-Fi, the *supplicant* must trust the RADIUS server's CA root — otherwise it can't validate the server it's authenticating to.
- Adding a rogue root to a device = total MITM. This is exactly how corporate TLS-inspection proxies work (legitimately) and how malware does it (maliciously).

### 5. Why Certificates Beat Passwords for Network Auth

This is the SecureW2 thesis — be ready to articulate it cold.

| Dimension | Password / PSK | Certificate (EAP-TLS) |
|-----------|----------------|------------------------|
| Phishable? | Yes — shared secret can be captured/replayed | No — private key never leaves the device, never transmitted |
| Over-the-wire exposure | Hash/challenge transmitted; crackable (MS-CHAPv2 is broken) | Only signatures cross the wire; private key stays put |
| Mutual authentication | Often one-way (client trusts AP blindly → evil-twin) | Mutual: client validates server cert AND server validates client cert |
| Credential sharing | Trivial (one PSK for the whole office) | Each device has a unique key pair |
| Rotation/expiry | Manual, painful, rarely done | Built-in validity + automated lifecycle (renew/revoke) |
| Breach blast radius | One leaked PSK = whole network | Revoke a single device cert |

**The killer point — evil-twin / MITM:** With PEAP-MSCHAPv2, a fake AP can harvest credentials because the client often doesn't properly validate the server. With **EAP-TLS**, the supplicant must validate the **RADIUS server's certificate** (issuer + name) *before* presenting its own — and the client never sends a reusable secret. That's "passwordless Wi-Fi," and it's why enterprises move to it.

### 6. Public PKI vs Private PKI

| | **Public (Web) PKI** | **Private (Enterprise/Internal) PKI** |
|---|----------------------|----------------------------------------|
| Roots | In every OS/browser trust store globally | In *your* devices' stores only (you distribute) |
| Governed by | CA/Browser Forum Baseline Requirements, audits (WebTrust) | Your own CP/CPS; no external mandate |
| Use case | Public-facing HTTPS, anything strangers must trust | Internal: 802.1X/EAP-TLS, VPN, device identity, internal services, code signing |
| Validation | DV/OV/EV domain & org validation | Bound to your IdP / directory / device posture |
| Cost/limits | Per-cert, rate limits, 90-day max lifetimes trending | You control issuance volume, lifetime, profiles |

**Key insight:** EAP-TLS Wi-Fi should use a **private PKI**, not a public one. Public CAs won't issue you a `clientAuth` cert with a UPN SAN for `vamsi@corp.local`, validity and policies are out of your control, and you don't *want* the whole internet's trust store involved — you want a closed loop where only your RADIUS server trusts your issuing CA. SecureW2 Cloud PKI is precisely a managed private PKI.

### 7. Web PKI vs Enterprise PKI — Different Threat Models

- **Web PKI** optimizes for "strangers trusting servers." Server-auth heavy, short lifetimes, Certificate Transparency logs, strict BR compliance, automated (ACME).
- **Enterprise PKI** optimizes for "known org authenticating its own users/devices to its own services." Client-auth heavy, ties to identity systems, custom EKUs/SANs, longer or policy-driven lifetimes, integrates with NAC/RADIUS/MDM. Revocation is *internal* (your OCSP/CRL), and you can enforce things a public CA never could (device posture, IdP group membership).

### 8. CP / CPS (brief)

- **Certificate Policy (CP):** the *what* — a named set of rules (an OID) saying what a cert under this policy means, who may get one, allowed uses, assurance level.
- **Certification Practice Statement (CPS):** the *how* — the operational document describing how the CA actually implements the CP (key protection, vetting procedures, revocation handling, audit). RFC 3647 defines the standard outline.
- Why care: in audits and federation, "which policy was this issued under?" is answered by the **Certificate Policies extension** (an OID) in the cert, linking back to the CP/CPS.

### 9. Trust Models

| Model | Structure | Where you see it |
|-------|-----------|------------------|
| **Hierarchical** | Single root → intermediates → leaves. Tree. | Almost all enterprise + web PKI. Simple, clear single trust anchor. |
| **Mesh / cross-certified** | Multiple CAs cross-sign each other; no single root. | Inter-organization federation. |
| **Bridge CA** | A neutral hub cross-certifies many independent PKIs so they interoperate without merging hierarchies. | US Federal Bridge CA, large gov/contractor ecosystems. |
| **Web of Trust** | No CAs; peers sign each other's keys, trust is transitive/subjective. | PGP/GPG. Doesn't scale to enterprise; mentioned for contrast. |

> **Cross-signing nuance (real-world):** the same logical CA can be issued *two* certificates — one chaining to an old widely-trusted root, one to a new root. This lets a new CA be trusted by old devices during a transition (Let's Encrypt's ISRG Root X1 cross-signed by IdenTrust DST Root CA X3 is the canonical example). Chain-building can therefore produce multiple valid paths; clients pick whichever terminates in a root they trust.

## PRACTICE

```bash
# ---------- Inspect the system trust store ----------
# Linux (Debian/Ubuntu): the trusted CA bundle
ls /etc/ssl/certs | head
openssl crl2pkcs7 -nocrl -certfile /etc/ssl/certs/ca-certificates.crt | \
  openssl pkcs7 -print_certs -noout | grep -i subject | head

# Windows (PowerShell): enumerate trusted roots
#   Get-ChildItem Cert:\LocalMachine\Root | Select-Object Subject, NotAfter | Sort-Object Subject
# macOS:
#   security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain

# ---------- View a real cert chain off a live server ----------
# -showcerts dumps every cert the server sends (leaf + intermediates, NOT the root)
openssl s_client -connect www.google.com:443 -servername www.google.com -showcerts </dev/null

# Just the chain summary (subject/issuer of each, plus the verify result)
echo | openssl s_client -connect www.google.com:443 -servername www.google.com 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates

# ---------- Verify a chain explicitly ----------
# Save the leaf and the intermediate(s), then verify against a root bundle:
openssl verify -CAfile root.pem -untrusted intermediate.pem leaf.pem
# Common outputs you must recognize:
#   leaf.pem: OK
#   error 20 at 0 depth lookup: unable to get local issuer certificate   <- missing intermediate/root
#   error 10 at 0 depth lookup: certificate has expired
#   error 19 at 1 depth lookup: self-signed certificate in chain         <- root not trusted

# ---------- Build your own tiny 2-tier hierarchy ----------
# Root
openssl req -x509 -newkey rsa:4096 -keyout rootCA.key -out rootCA.pem -days 3650 -nodes \
  -subj "/CN=Demo Root CA/O=SecureW2 Lab"
# Intermediate CSR + signed by root (BasicConstraints CA:TRUE via -addext)
openssl req -newkey rsa:2048 -keyout int.key -out int.csr -nodes -subj "/CN=Demo Issuing CA"
openssl x509 -req -in int.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
  -days 1825 -out int.pem -extfile <(printf "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign")
# Verify the intermediate chains to the root
openssl verify -CAfile rootCA.pem int.pem
```

**Exercises:**
1. Pull the cert chain from `www.google.com` and from your bank. Identify the leaf, intermediate(s), and the root each chains to. Confirm the server did **not** send the root.
2. Save a leaf + intermediate, then run `openssl verify` *without* `-untrusted intermediate.pem`. Reproduce the "unable to get local issuer certificate" error, then fix it.
3. Build the 2-tier hierarchy above. Use `openssl verify` to prove the intermediate validates against the root. Then try verifying the intermediate against an empty/ wrong CA file and read the error code.
4. On your OS, locate one root CA in the trust store and one that you suspect is enterprise-injected (e.g., a corporate proxy root). Explain how the second one enables legitimate TLS inspection.
5. Write 3 sentences explaining to a non-expert manager why EAP-TLS certs stop evil-twin attacks that PEAP-MSCHAPv2 does not.
6. For a SecureW2-style passwordless Wi-Fi rollout, decide: public or private PKI? Justify using EKU, SAN, lifetime control, and trust-store distribution.

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. A root certificate is self-signed. So what actually makes it trustworthy — and why isn't the self-signature meaningless?**
The self-signature only proves internal consistency (the key matches the cert body); it provides zero trust on its own — anyone can self-sign. Trust comes entirely from the root being present in the relying party's **trust store**, which got there through an out-of-band process: an OS/browser vendor's audited root program, or an enterprise admin pushing it via MDM/GPO. So trust is bootstrapped by distribution and human/organizational vetting, not by cryptography. Cryptography then *carries* that trust down the chain to leaves.

**Q2. Why issue from an intermediate CA instead of signing leaf certs directly with the root?**
To protect the root's private key, which is effectively irreplaceable — it's in millions of trust stores with a multi-decade lifetime and can't be rotated quickly. By keeping the root **offline in an HSM** and doing all day-to-day issuance from intermediates, a compromise can be contained by revoking and replacing the intermediate without touching the root. It also enables operational flexibility (per-purpose issuing CAs, name constraints, cross-signing for transitions). Signing leaves directly from the root would force the root to be online and turn any incident into a catastrophe.

**Q3. EAP-TLS is "mutual authentication." Concretely, what does each side validate, and what breaks if the client skips its half?**
The RADIUS server validates the client's certificate (chain to the trusted issuing CA, validity, `clientAuth` EKU, revocation, and often a SAN identity mapped to the directory). The client (supplicant) must validate the **server's** certificate: that it chains to the expected CA root *and* matches the configured server name/SAN. If the client skips server validation — a depressingly common misconfiguration — an attacker stands up an evil-twin AP with their own RADIUS server, the client connects and presents... but with EAP-TLS the client's secret never leaves the device, so the worst case is still far better than PEAP. The real danger of skipping server validation is in tunneled methods (PEAP/TTLS) where the inner password *is* exposed; for EAP-TLS it primarily lets you be lured onto a hostile network. Either way, "validate the server cert and name" is mandatory configuration.

**Q4. Why should enterprise EAP-TLS use a private PKI rather than buying client certs from a public CA?**
Public CAs are bound by CA/Browser Forum rules: they won't issue certs with internal-only identities (a UPN like `user@corp.local` as a SAN), you can't control profiles/EKUs/lifetimes the way 802.1X needs, and you'd be entangling your network auth with the entire global trust ecosystem and its rate limits and revocation logs. A private PKI gives you a closed loop: only your RADIUS server trusts your issuing CA, you mint `clientAuth` certs with exactly the SAN identities your directory expects, and you own revocation. SecureW2 Cloud PKI is exactly this — a managed private CA wired to your IdP.

**Q5. What's the difference between a CA and an RA, and why does the distinction matter even in a cloud product where they're the same vendor?**
The RA performs **identity vetting and authorization** — confirming the requester is who they claim before any cert is issued; the CA performs the **cryptographic signing** and key/cert lifecycle management. The distinction matters because the security of the whole system hinges on the RA: a perfectly secured CA that signs whatever it's told is worthless. In SecureW2's model the "RA" is the onboarding flow that authenticates the user to Azure AD/Okta/Google and checks group/posture before the managed CA signs — so an interviewer testing depth wants you to locate *where identity is actually proven*, which is the RA, not the signing key.

**Q6. A server's TLS cert validates fine on your laptop but users report "untrusted" errors. The cert and key are correct. What's the most likely cause?**
An **incomplete certificate chain**: the server is sending only the leaf and omitting one or more intermediates. Your laptop validated because it had cached or pre-installed that intermediate from a prior connection, but fresh clients can't build the path to a trusted root and fail with "unable to get local issuer certificate." The fix is to configure the server to send the full chain (leaf + all intermediates, excluding the root, which clients supply from their trust store). Diagnose with `openssl s_client -showcerts` and tools like SSL Labs that flag chain issues.

**Q7. Explain cross-signing and why a single CA might have its public key inside two different certificates.**
Cross-signing issues the same CA public key in multiple certificates that chain to *different* roots, so the CA can be trusted by device populations that only have one root or the other. The textbook case is a new root that's not yet in older devices' trust stores: the new CA gets a second certificate signed by an established, widely-trusted legacy root, giving an alternate valid path during the transition (Let's Encrypt's ISRG root cross-signed by IdenTrust's DST root). Clients build whichever chain ends in a root they trust, so the same leaf can validate via multiple paths. It's the standard tool for rolling out new roots without breaking old clients.

**Q8. Why are certificates fundamentally better than a shared PSK for Wi-Fi, beyond just "they're stronger"?**
The core difference is that a certificate's private key is a **per-device secret that is never transmitted**, while a PSK is a **shared secret that every device knows and that gets exposed in the handshake** (and, with PMK derivations, can be attacked). A PSK can't be revoked per-device — leak it once and you re-key the entire network; a cert is revoked individually. Certs also carry verifiable identity (mapped to your directory) and built-in expiry/lifecycle, enabling automated rotation. So it's not just cryptographic strength — it's non-phishability, per-device revocation, identity binding, and lifecycle management all at once, which is the whole "passwordless" pitch.

➡ Next: [Day 03 — X.509 Certificate Structure](day-03-x509-certificates-structure.md)
