# Day 18 — Identity Providers & Federation

> "A certificate is only as trustworthy as the identity it was minted from. Federation is how we prove *who* before we issue the *what*." — the whole game of cert-based onboarding in one sentence.

Today we connect the dots between **who a user is** (identity), **who vouches for them** (the IdP), and **how that identity gets cryptographically frozen into a client certificate** (enrollment). This is the layer that sits *above* PKI and *feeds* it. If you understand this, you understand why SecureW2 integrates with Entra ID, Okta, Google Workspace, Ping, and on-prem AD — and what actually happens when a user clicks "Sign in with Google" before getting a Wi-Fi cert.

---

## THEORY

### 1. Identity Store vs Identity Provider (IdP) — they are NOT the same

People conflate these constantly. Be precise.

| Concept | What it is | Examples | Speaks |
|---|---|---|---|
| **Identity Store / Directory** | The *database* of users, groups, attributes, passwords/hashes | Active Directory, OpenLDAP, a SQL user table | LDAP, Kerberos, proprietary |
| **Identity Provider (IdP)** | A service that **authenticates** a user against a store and then **asserts** that identity to other apps via a federation protocol | Entra ID (Azure AD), Okta, Google Workspace, Ping, ADFS | SAML, OIDC, WS-Fed |

Key insight:
- **AD by itself is a directory.** You query it (LDAP bind/search) or authenticate against it (Kerberos/NTLM). It does not "federate."
- **ADFS / Entra ID turns AD into an IdP** — it sits in front of the directory and emits SAML assertions / OIDC tokens to relying apps.
- **Entra ID (Azure AD)** is a cloud directory *and* an IdP. **Okta** is primarily an IdP that can also be a directory (Universal Directory) and an aggregator of *other* directories (it can broker AD, Google, etc.).
- **Google Workspace** = directory + IdP (SAML/OIDC). **Ping** = IdP/federation broker.

**Why it matters for PKI:** The *store* holds the authoritative attributes (UPN, email, group membership, department). The *IdP* is what an onboarding system trusts to assert those attributes during enrollment. SecureW2's enrollment policies key off **group membership** read from the IdP at sign-in time.

### 2. Federation — the core idea

**Federation** = an application (the **Service Provider / Relying Party**) outsources authentication to a trusted third party (the **IdP**), instead of holding the user's password itself.

- The app and IdP establish a **trust relationship** out-of-band: they exchange **metadata** and **signing certificates/keys**.
- At runtime the user authenticates *at the IdP*, and the IdP hands the app a **signed token** ("this is alice@corp.com, member of Engineering, MFA satisfied").
- The app never sees the password. This enables **SSO** (one login, many apps) and centralized policy/MFA.

The two dominant protocols: **SAML 2.0** (XML, enterprise/web SSO) and **OpenID Connect** (JSON/JWT, modern apps + mobile). Older: WS-Federation (Microsoft).

### 3. SAML 2.0 — the enterprise workhorse

**Actors:**
- **IdP (Identity Provider)** — authenticates the user, issues the **assertion**.
- **SP (Service Provider)** — the app the user wants in to (the "relying party"). In onboarding, *the enrollment portal is the SP*.

**The assertion** is a signed XML blob containing:
- **Subject** (the NameID — e.g. `alice@corp.com`)
- **Conditions** (NotBefore / NotOnOrAfter — validity window, audience restriction)
- **AuthnStatement** (how/when they authenticated, MFA context)
- **AttributeStatement** (the gold: email, displayName, **groups/roles**, department)
- An **XML Signature** (`<ds:Signature>`) over the assertion or response, signed with the IdP's private key.

**SP-initiated SSO flow (Redirect → POST), the common case:**

```text
1. User hits SP (enrollment portal). SP has no session.
2. SP builds a SAML AuthnRequest, sends user to IdP
   via HTTP-Redirect (request is deflated+base64 in URL).
3. IdP authenticates user (password + MFA / existing SSO session).
4. IdP builds a signed SAML Response containing the Assertion.
5. IdP returns an auto-submitting HTML form -> browser POSTs
   the base64 Response to the SP's Assertion Consumer Service (ACS) URL.
6. SP validates the signature (using IdP cert from metadata),
   checks Conditions/Audience/timestamps, reads attributes,
   creates a local session. User is in.
```

**Bindings:** AuthnRequest typically uses **HTTP-Redirect** (GET, compact); the Response uses **HTTP-POST** (too big for a URL). There's also Artifact binding (back-channel) — rare.

**Metadata** is the trust contract — an XML file each side publishes containing:
- EntityID (unique identifier)
- ACS / SSO endpoints
- **Signing certificate(s)** (X.509, used to verify signatures)
- NameID format, supported bindings

**Signing vs encryption:** Assertions are almost always **signed** (integrity + authenticity). They *may* also be **encrypted** (confidentiality) if the SP publishes an encryption cert. Sign the **Response**, the **Assertion**, or both — best practice: sign the assertion at minimum.

**Gotchas:**
- **Clock skew** kills SAML — `NotOnOrAfter` is short (minutes). NTP everywhere.
- **Audience mismatch** (wrong EntityID) → "responder" errors.
- **Expired/rotated IdP signing cert** not updated in SP metadata → all logins fail. Automate metadata refresh.

### 4. OAuth 2.0 — authorization, NOT authentication

Repeat after me: **OAuth 2.0 is an *authorization* framework. It answers "what can this app do on the user's behalf," not "who is this user."** Using raw OAuth to "log in" is a known anti-pattern (the access token doesn't authenticate the *user* to *you*).

**Four roles:**
- **Resource Owner** — the user.
- **Client** — the app wanting access.
- **Authorization Server (AS)** — issues tokens (the IdP).
- **Resource Server** — the API holding the protected data (accepts access tokens).

**Grant types (how a client gets a token):**
| Grant | Use case | Notes |
|---|---|---|
| **Authorization Code + PKCE** | Web apps, SPAs, **mobile/native** | The modern default. PKCE mandatory for public clients. |
| Client Credentials | Machine-to-machine (no user) | SCIM provisioning, service accounts. |
| Device Code | TVs, CLI, input-constrained devices | User authorizes on a second device. |
| ~~Implicit~~ | (deprecated) | Tokens in URL fragment — insecure. |
| ~~Resource Owner Password~~ | (deprecated) | App handles the password — defeats the point. |

**Authorization Code + PKCE flow:**
```text
1. Client generates code_verifier (random), derives
   code_challenge = BASE64URL(SHA256(verifier)).
2. Client -> AS authorize endpoint with code_challenge + scopes.
3. User authenticates & consents at AS.
4. AS redirects back with a short-lived authorization CODE.
5. Client -> AS token endpoint: code + code_verifier.
6. AS verifies SHA256(verifier)==challenge, returns
   access_token (+ refresh_token, + id_token if OIDC).
```
PKCE (Proof Key for Code Exchange) stops an attacker who intercepts the redirect code from redeeming it — they lack the `code_verifier`.

**Tokens & scopes:**
- **Access token** — bearer credential for the Resource Server. Often a JWT, sometimes opaque. Short-lived.
- **Refresh token** — long-lived, exchanges for new access tokens.
- **Scopes** — coarse permission labels (`read:profile`, `mail.send`). *Authorization*, not identity.

### 5. OpenID Connect (OIDC) — authentication ON TOP of OAuth 2.0

OIDC is a thin **identity layer over OAuth 2.0**. It adds the missing "who is the user" answer.

- Add scope **`openid`** → the AS (now an **OpenID Provider / OP**) returns an **ID Token** alongside the access token.
- **ID Token = a JWT** asserting the user's identity. Claims: `sub` (stable subject id), `iss` (issuer), `aud` (client id), `exp`/`iat`, `email`, `name`, `groups`, plus `nonce` and `auth_time`.
- The ID token is **signed (JWS)** by the OP — verify it with the OP's public key from the **JWKS** endpoint (`/.well-known/openid-configuration` → `jwks_uri`).
- **UserInfo endpoint** — call with the access token to fetch additional profile claims.

**JWT structure** — three base64url parts separated by dots:
```text
header.payload.signature
{"alg":"RS256","typ":"JWT","kid":"abc"} . {"sub":"...","email":"..."} . <RSA signature>
```
Header says the algo + key id; payload is the claims; signature proves it wasn't tampered with. **The payload is NOT encrypted — it's only base64. Never put secrets in a JWT payload.**

**OAuth vs OIDC cheat line for interviews:**
> OAuth gives you a valet key to a car (authorization). OIDC gives you the driver's license of the person holding the key (authentication). SAML does the license thing too, in XML, for enterprise web SSO.

### 6. SCIM — provisioning and (critically) DEPROVISIONING

Federation handles *authentication at login time*. But apps often need user accounts/attributes to exist *before* and *after* login. **SCIM 2.0 (System for Cross-domain Identity Management)** is the REST/JSON standard for the IdP to **push** user lifecycle into downstream apps.

- Endpoints: `/Users`, `/Groups` with standard JSON schemas.
- Operations: create, update, **deactivate/delete**, group membership sync.
- Driven by the IdP (Entra/Okta) as a CRUD client; the app exposes a SCIM endpoint.

**Why it matters for PKI lifecycle:** When HR offboards someone, the IdP **SCIM-deletes** the user → the connected system can **trigger certificate revocation**. SCIM is the plumbing that makes "user disabled = cert revoked" automatic instead of manual. *Authentication federation alone won't revoke a cert that's already on a laptop — provisioning sync (SCIM) closes that gap.*

### 7. How federation FEEDS certificate enrollment (the SecureW2 pattern)

This is the heart of the day. EAP-TLS needs a **client certificate** on the device. How does the right identity get into that cert? Federation.

```text
1. User opens the onboarding portal (the SP / OIDC client).
2. Portal redirects to the IdP (Entra / Okta / Google) — SAML or OIDC.
3. User authenticates (password + MFA) AT THE IDP.
4. IdP returns the assertion/ID token with attributes:
      UPN/email, displayName, department, GROUPS.
5. Onboarding system reads those attributes and applies a
   POLICY: "Engineering -> 1yr cert, OU=Eng; Contractors -> 90d."
6. A CSR is generated (key on the device, never leaves it),
   and the system issues a client cert with the IDP IDENTITY
   BAKED INTO THE SUBJECT / SAN:
        SAN: rfc822Name = alice@corp.com
        SAN: otherName/UPN = alice@corp.com
        CN  = alice@corp.com  (or device id)
7. Cert + Wi-Fi profile (EAP-TLS, trusted CA, server name) installed.
```

The result: **the live IdP identity is cryptographically frozen into the certificate at enrollment time.** From then on the device proves identity with the cert — no password, no IdP round-trip needed for Wi-Fi. This is exactly how SecureW2 ties **Entra/Okta/Google** identity to a **device certificate**.

### 8. Cert-based auth vs PEAP — the directory-lookup difference

| | **PEAP-MSCHAPv2 (credential)** | **EAP-TLS (certificate)** |
|---|---|---|
| What's presented | username + password (MSCHAPv2 inside TLS tunnel) | client certificate |
| RADIUS must... | **do an LDAP/AD lookup/bind** every auth to validate the password and read groups | **validate the cert chain + OCSP/CRL + SAN** — *no directory lookup required* |
| Dependency | live, fast, available AD at every connect | CA trust + revocation status only |
| Failure mode | AD down → no Wi-Fi; password expiry breaks Wi-Fi; MSCHAPv2 is weak | cert expiry/revocation; needs onboarding |
| Group policy | read from AD/IdP at auth time | **attributes are already in the SAN** — RADIUS can policy on them directly |

**The "why":** With PEAP, the directory is in the hot path of *every* authentication. With EAP-TLS, the identity work happened **once at enrollment** (via federation), and runtime auth is pure crypto. That's why cert-based scales better and survives directory outages — and why SecureW2 pushes customers from PEAP to EAP-TLS.

### 9. Group-based policy

Groups are the currency of access. They flow:
```text
AD/Entra group  --(SAML attr / OIDC claim)-->  onboarding policy
   --> cert OU/SAN/template  --> RADIUS policy (VLAN, ACL, allow/deny)
```
- At **enrollment**: group decides cert validity, template, SAN content, even *whether to issue at all*.
- At **RADIUS time**: policy maps the cert's attributes/OU → **VLAN assignment**, dACL, or rejection (RADIUS Access-Accept with VSAs / Tunnel attributes).

---

## PRACTICE

### A. Decode a SAML assertion (it's base64'd XML)

A SAML Response posted to the ACS arrives base64-encoded. Decode it.

```bash
# Save the SAMLResponse form field value to resp.b64, then:
base64 -d resp.b64 > assertion.xml          # Linux/macOS
# Windows PowerShell equivalent:
#   [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-Content resp.b64 -Raw))) > assertion.xml

xmllint --format assertion.xml | less        # pretty-print

# Pull the interesting bits:
xmllint --xpath "//*[local-name()='NameID']/text()" assertion.xml
xmllint --xpath "//*[local-name()='Attribute']" assertion.xml
xmllint --xpath "//*[local-name()='Conditions']" assertion.xml   # NotBefore/NotOnOrAfter/Audience
```

Note: a SAML **AuthnRequest** in a redirect URL is *deflate*-compressed THEN base64'd — you must raw-inflate after base64-decoding (`openssl zlib`/`python -c "import zlib,sys,base64;sys.stdout.write(zlib.decompress(base64.b64decode(open('r.b64').read()),-15).decode())"`). The **Response** (POST binding) is usually just base64, no deflate.

### B. Decode a JWT (ID token) without any library

A JWT is `header.payload.signature`, each part **base64url** (URL-safe: `-` `_`, no padding). Conceptually this is what jwt.io does in your browser — but do it locally so you never paste a real token into a website.

```bash
JWT='eyJhbGciOiJSUzI1NiIsImtpZCI6ImFiYyJ9.eyJzdWIiOiJhbGljZSIsImVtYWlsIjoiYWxpY2VAY29ycC5jb20iLCJncm91cHMiOlsiRW5nIl19.SIGNATURE'

# Helper: base64url -> base64, pad, decode
b64url () { echo "$1" | tr '_-' '/+' | awk '{ l=length%4; if(l>0) printf "%s%s\n", $0, substr("===",1,4-l); else print }' | base64 -d; }

b64url "$(echo "$JWT" | cut -d. -f1)" ; echo   # HEADER  -> alg, kid, typ
b64url "$(echo "$JWT" | cut -d. -f2)" ; echo   # PAYLOAD -> sub, email, groups, exp, iss, aud
# part 3 is the signature (binary) — verified against JWKS, not human-read
```

**Verify** the signature properly: fetch the OP's keys from `https://op.example.com/.well-known/openid-configuration` → `jwks_uri`, match the `kid`, and check the RS256 signature. Tools: `jwt`, `step crypto jwt verify`, or any OIDC library. **Decoding ≠ verifying** — anyone can read a JWT; only the signature proves it's authentic.

```bash
# Discovery doc (memorize this URL — it's the entry point to everything):
curl -s https://login.microsoftonline.com/<tenant>/v2.0/.well-known/openid-configuration | jq '{issuer, authorization_endpoint, token_endpoint, jwks_uri, userinfo_endpoint}'
```

### C. Conceptual SCIM sync (provision + deprovision)

```text
# IdP (Okta/Entra) acts as SCIM client; the app exposes /scim/v2

# Provision a user:
POST /scim/v2/Users
{ "schemas":["urn:ietf:params:scim:schemas:core:2.0:User"],
  "userName":"alice@corp.com",
  "name":{"givenName":"Alice","familyName":"Ng"},
  "emails":[{"value":"alice@corp.com","primary":true}],
  "active": true }

# Add to a group:
PATCH /scim/v2/Groups/<eng-id>
{ "Operations":[{"op":"add","path":"members","value":[{"value":"<alice-id>"}]}] }

# DEPROVISION (offboarding) — this is the lifecycle hook:
PATCH /scim/v2/Users/<alice-id>
{ "Operations":[{"op":"replace","value":{"active": false}}] }
   --> downstream system should REVOKE alice's client certificate.
```

**Exercises:**
1. Capture a SAML Response from a browser dev-tools network tab, base64-decode it, and identify: the NameID, the `NotOnOrAfter`, the Audience, and every group attribute.
2. Take any OIDC ID token (use a test token), decode header and payload with the `b64url` helper above. Identify `iss`, `aud`, `sub`, `exp` — then explain why decoding alone proves *nothing* about authenticity.
3. Find your IdP's discovery URL and `curl | jq` it. Note the `jwks_uri` and `userinfo_endpoint`.
4. Write a one-paragraph runbook: "When SCIM marks a user inactive, here is exactly what must happen to their certificate and why a simple IdP login block is insufficient."
5. Draw the data flow: Entra group → SAML attribute → cert SAN → RADIUS VLAN assignment. Label every protocol hop.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. A candidate says "we use OAuth to log users in." What's wrong, and what should they say instead?**
OAuth 2.0 is *authorization*, not *authentication* — an access token says "this app may call this API," not "this is Alice." Using a bare access token as proof of login is the classic anti-pattern (an access token issued for another client can be replayed). The correct answer is **OpenID Connect**: add the `openid` scope, get back a signed **ID token (JWT)** with verified user claims (`sub`, `iss`, `aud`, `nonce`), and validate it against the OP's JWKS. OIDC = authentication; OAuth = authorization. SAML is the XML enterprise equivalent of OIDC's authentication.

**Q2. If EAP-TLS uses a client certificate, why do we still integrate with Entra/Okta at all?**
Federation runs at **enrollment time**, not auth time. The IdP authenticates the user (with MFA) *once* and supplies the attributes (UPN, groups) that get **baked into the certificate's SAN**. After that, EAP-TLS authentication is pure crypto — no IdP round-trip. So the IdP isn't in the Wi-Fi hot path; it's the trusted source that decided *who this cert represents and what policy applies* when the cert was minted. Lose that step and you'd be issuing certs to unverified users.

**Q3. PEAP-MSCHAPv2 vs EAP-TLS: which one hammers your directory, and what breaks when AD goes down?**
PEAP-MSCHAPv2 requires the RADIUS server to validate the password against AD/LDAP on **every** authentication and read groups live — AD outage = no one connects, and password expiry/lockout silently breaks Wi-Fi. EAP-TLS does **no directory lookup**: it validates the cert chain, checks revocation (OCSP/CRL), and reads policy attributes straight from the SAN. AD can be down and certificate-authenticated devices keep connecting. This is the core scalability and resilience argument for moving off PEAP.

**Q4. Your SAML logins suddenly all fail with no config change on your side. First three things you check?**
(1) **IdP signing certificate rotation** — the IdP rolled its cert and your SP metadata still trusts the old one; signature validation now fails. (2) **Clock skew** — `NotOnOrAfter` windows are minutes wide; an NTP drift on SP or IdP invalidates every assertion. (3) **Metadata/endpoint or EntityID/Audience mismatch** — an ACS URL or audience changed. Fix: automate metadata refresh, enforce NTP, and monitor IdP cert expiry.

**Q5. Where is the actual identity in an EAP-TLS world — the IdP, the directory, or the certificate?**
At authentication time, the **certificate is the identity** — specifically the SAN (rfc822Name/UPN). The IdP and directory were the *authoritative source* that the certificate was derived from at enrollment, but they aren't consulted during Wi-Fi auth. This is why **revocation** matters so much: since the cert is self-contained, the only way to kill access is CRL/OCSP. It's also why offboarding must trigger revocation, not just an IdP account disable.

**Q6. A user is offboarded in HR. Walk the chain that should revoke their network access.**
HR system → IdP deprovisions the user → **SCIM** PATCH `active:false` (or delete) hits connected systems → the certificate-management system **revokes the user's client cert** and publishes it to CRL / OCSP → next time the device authenticates, RADIUS gets a "revoked" status and rejects EAP-TLS. The trap: disabling the IdP account alone does **nothing** to a cert already sitting on the laptop, because EAP-TLS doesn't call the IdP. Revocation is the only real off-switch.

**Q7. Why is the JWT payload base64 and not encrypted — isn't that insecure?**
A standard signed JWT (JWS) provides **integrity and authenticity**, not confidentiality. The payload is base64url-encoded (trivially decodable) and protected by a signature so it can't be *tampered* with. That's fine because the claims (sub, email, groups) usually aren't secret, and TLS protects them in transit. You must never place secrets in a JWT. If confidentiality of claims is required, use **JWE** (encrypted JWT). Interview red flag: anyone who says "the JWT is encrypted so it's safe to put a password in."

**Q8. What's PKCE and which clients must use it?**
PKCE (Proof Key for Code Exchange) binds an authorization-code exchange to the client that started it. The client creates a random `code_verifier`, sends `SHA256(verifier)` as the `code_challenge` on the authorize request, and presents the raw verifier when redeeming the code. An attacker who intercepts the redirect code can't redeem it without the verifier. It's **mandatory for public clients** (SPAs, mobile/native apps that can't keep a secret) and recommended for all. In onboarding, the JoinNow-style native app uses Authorization Code + PKCE.

**Q9. Okta sits in front of on-prem AD. Is Okta the directory or the IdP — and where do the groups come from?**
Both/neither cleanly: Okta is acting as the **IdP/broker**, while on-prem **AD is the authoritative store**. Okta imports/syncs AD users and groups (via AD agent) into its Universal Directory, then *asserts* those groups in SAML/OIDC to your SP. So at enrollment the groups originate in AD, are surfaced by Okta as assertion attributes, and land in the certificate. Knowing which system is authoritative for group membership matters when a policy decision looks wrong — you debug at the source, not the broker.

---

➡ Next: [Day 19 — Device Onboarding & BYOD](day-19-device-onboarding-byod-scep-mdm.md)
