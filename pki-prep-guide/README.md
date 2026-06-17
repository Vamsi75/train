# PKI, Certificate Lifecycle & RADIUS — Zero to Hero

A complete, day-wise learning + interview-prep track covering **Public Key Infrastructure (PKI)**, **Certificate Lifecycle Management (CLM)**, and **RADIUS / 802.1X / EAP network authentication** — written from the perspective of a SecureW2-style passwordless-network-security practitioner.

By the end you should be able to design a CA hierarchy, run a certificate-based Wi-Fi/VPN authentication system end-to-end, automate the whole certificate lifecycle, and debug an EAP-TLS failure or a midnight cert-expiry outage without notes.

Each day follows the same rhythm:

> **Theory** → **Hands-on Practice** → **Twisted / Important Interview Questions**

---

## How to use this guide

1. **Do the practice.** Almost everything here can be reproduced locally with **OpenSSL** and **FreeRADIUS** (Docker is easiest — see [`_setup/lab-setup.md`](_setup/lab-setup.md)). Reading about a TLS handshake ≠ having watched one in Wireshark.
2. **Answer the interview questions out loud first.** The "twisted" ones are exactly what separates someone who *configured* a RADIUS server once from someone who *understands* certificate-based auth.
3. **Think in terms of trust, identity, and lifecycle.** Every topic ladders up to three questions: *Who do I trust? How do I prove identity? What happens when something expires or is compromised?*
4. **Pace:** ~2–3 hrs/day. Whole track ≈ 4–6 weeks part-time, compressible to ~2 weeks full-time.

---

## Curriculum at a glance

### Phase 1 — Crypto & PKI Foundations (Days 1–5)
| Day | Topic |
|-----|-------|
| [Day 01](day-01-cryptography-foundations.md) | Cryptography foundations — symmetric, asymmetric, hashing, digital signatures, key exchange |
| [Day 02](day-02-pki-fundamentals-trust-model.md) | What PKI is — components (CA/RA/VA), the trust model, why certificates beat passwords |
| [Day 03](day-03-x509-certificates-structure.md) | X.509 certificates — fields, extensions, OIDs, SAN, key usage |
| [Day 04](day-04-encoding-formats-pkcs.md) | Encodings & formats — DER/PEM, the PKCS family, PFX/P12, keystores |
| [Day 05](day-05-ca-hierarchy-chain-of-trust.md) | CA hierarchy — root, intermediate/issuing CAs, chain of trust, offline root, cross-signing |

### Phase 2 — Certificate Lifecycle Management (Days 6–11)
| Day | Topic |
|-----|-------|
| [Day 06](day-06-keys-csr-hsm-key-management.md) | Key generation, CSRs, key storage, HSMs & key ceremonies |
| [Day 07](day-07-enrollment-protocols-scep-est-acme.md) | Enrollment protocols — manual, SCEP, EST, ACME, CMP |
| [Day 08](day-08-certificate-issuance-templates-policies.md) | Issuance, certificate templates/profiles, CP/CPS, validation levels |
| [Day 09](day-09-certificate-lifecycle-renewal-rotation.md) | The lifecycle — enrollment → renewal → rotation → expiry, automation |
| [Day 10](day-10-revocation-crl-ocsp.md) | Revocation — CRL, OCSP, OCSP stapling, short-lived certs |
| [Day 11](day-11-clm-automation-discovery.md) | CLM platforms — discovery, inventory, outage prevention, crypto-agility |

### Phase 3 — TLS & Network Authentication (Days 12–17)
| Day | Topic |
|-----|-------|
| [Day 12](day-12-tls-handshake-mtls.md) | TLS/SSL handshake deep dive, mutual TLS (mTLS) |
| [Day 13](day-13-aaa-radius-fundamentals.md) | AAA model & RADIUS protocol fundamentals |
| [Day 14](day-14-radius-deep-attributes-radsec-proxy.md) | RADIUS deep — packet types, attributes/VSAs, RadSec, proxying, accounting |
| [Day 15](day-15-8021x-eap-framework.md) | 802.1X port-based access control & the EAP framework |
| [Day 16](day-16-eap-methods-eap-tls-peap-ttls-teap.md) | EAP methods — EAP-TLS, PEAP, EAP-TTLS, TEAP, and why EAP-TLS wins |
| [Day 17](day-17-wpa-enterprise-wireless-8021x-flow.md) | WPA2/WPA3-Enterprise — the full wireless 802.1X auth flow |

### Phase 4 — Identity, Onboarding & the SecureW2 Platform (Days 18–21)
| Day | Topic |
|-----|-------|
| [Day 18](day-18-identity-providers-federation-saml-oidc.md) | Identity providers & federation — SAML, OAuth2/OIDC, SCIM, Entra ID/Okta/Google |
| [Day 19](day-19-device-onboarding-byod-scep-mdm.md) | Device onboarding & BYOD — self-service, SCEP + MDM (Intune/Jamf), gateways |
| [Day 20](day-20-securew2-platform-architecture.md) | SecureW2 platform architecture — Cloud RADIUS, Managed PKI, JoinNow, connectors |
| [Day 21](day-21-authorization-dynamic-vlan-nac-segmentation.md) | Authorization — dynamic VLAN, RADIUS policy, NAC, segmentation |

### Phase 5 — Security, Production & Expert (Days 22–25)
| Day | Topic |
|-----|-------|
| [Day 22](day-22-security-threats-crypto-agility-pqc.md) | Threats & best practices — CA compromise, key protection, crypto-agility, post-quantum |
| [Day 23](day-23-troubleshooting-production-playbook.md) | **Real-time production issues — playbook** (expiry outages, EAP failures, RADIUS debugging) |
| [Day 24](day-24-twisted-interview-questions.md) | **Twisted interview questions — master set** |
| [Day 25](day-25-mock-interview-capstone.md) | Mock interview, scenario rounds, design capstone |

---

## Supporting files
- [`_setup/lab-setup.md`](_setup/lab-setup.md) — build a local lab: OpenSSL CA + FreeRADIUS + a test supplicant, Wireshark tips
- [`_cheatsheets/openssl-commands-cheatsheet.md`](_cheatsheets/openssl-commands-cheatsheet.md) — one-page OpenSSL / certutil / RADIUS command reference
- [`_cheatsheets/interview-rapidfire.md`](_cheatsheets/interview-rapidfire.md) — 100 rapid-fire Q&A for the day before an interview

---

## What "hero / 20-years-experience" actually means here
By the end you should be able to, *without notes*:
- Draw a 2-tier CA hierarchy and justify why the root is offline.
- Read an X.509 dump and explain every critical extension (BasicConstraints, KeyUsage, EKU, SAN, AIA, CDP).
- Choose between CRL, OCSP, OCSP stapling, and short-lived certs — and defend it.
- Explain the full EAP-TLS handshake over 802.1X frame by frame, and where mutual authentication actually happens.
- Compare EAP-TLS vs PEAP-MSCHAPv2 and say *exactly* why passwords-over-the-air are the risk.
- Automate enrollment with SCEP/ACME and design renewal so nothing ever silently expires.
- Debug "the new laptops can't get on Wi-Fi" from the RADIUS logs to root cause.
- Wire an IdP (Entra/Okta/Google) to a SCEP-based BYOD onboarding flow and a Cloud RADIUS server.

Start with [`_setup/lab-setup.md`](_setup/lab-setup.md), then [Day 01](day-01-cryptography-foundations.md).

---

> "Trust is built in certificates and destroyed in expirations." — every PKI engineer, eventually.