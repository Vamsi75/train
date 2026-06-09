# Day 18 — JWT, OAuth2 Resource Server & Method Security

## THEORY

### 1. OAuth2 roles & flows (vocabulary)
- **Resource Owner** — the user.
- **Client** — the app requesting access on the user's behalf.
- **Authorization Server** — issues tokens (Keycloak, Okta, Auth0, Azure AD, Spring Authorization Server).
- **Resource Server** — your API, which **validates tokens** and serves protected resources.
**Grant types:** Authorization Code (+ **PKCE** for public clients) for user login; **Client Credentials** for service-to-service (no user) — this is exactly what cent's `JamfOAuthIdentityProvider` toggles between (`PASSWORD_BASIC_AUTH` vs `CLIENT_CREDENTIALS`). The implicit and password grants are **deprecated**.

### 2. JWT structure
`header.payload.signature` (Base64URL). 
- **Header:** alg (e.g., RS256), type.
- **Payload (claims):** `sub`, `iss`, `aud`, `exp`, `iat`, `scope`/`scp`, custom claims (roles, tenant).
- **Signature:** signs header+payload with the issuer's key (HMAC secret or RSA/EC private key).
A JWT is **signed, not encrypted** by default — anyone can read the payload (Base64-decode it). Never put secrets in a JWT. (Encryption is JWE, separate.)

### 3. JWT validation (what a resource server does)
1. Verify **signature** against the issuer's key (for RS256, the **public key from the JWKS endpoint**; the resource server fetches/caches the JWKS).
2. Check **`exp`** (not expired), **`iss`** (trusted issuer), **`aud`** (intended for this API), **`nbf`**.
3. Map claims (`scope`, roles) to authorities.
No DB lookup needed → **stateless, fast**.

### 4. Resource server config (Spring Security 6)
```java
@Bean
SecurityFilterChain api(HttpSecurity http) throws Exception {
    http
      .authorizeHttpRequests(a -> a
          .requestMatchers("/api/admin/**").hasAuthority("SCOPE_admin")
          .anyRequest().authenticated())
      .oauth2ResourceServer(o -> o.jwt(jwt ->
          jwt.jwtAuthenticationConverter(customConverter())))   // map claims → authorities
      .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
      .csrf(c -> c.disable());
    return http.build();
}
```
```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth.cent.example.com/realms/cent   # discovers JWKS automatically
```

### 5. The JWT revocation problem (key interview topic)
JWTs are **self-contained and valid until `exp`** — you can't "log out" a token server-side without extra machinery. Mitigations:
- **Short-lived access tokens** (e.g., 5–15 min) + **refresh tokens** (revocable, stored server-side).
- A **denylist** of revoked token ids (`jti`) checked per request (reintroduces state, but only for revoked ones).
- **Token versioning** per user (bump a value that invalidates old tokens).
Trade-off: statelessness vs immediate revocation. This is the central JWT design tension.

### 6. Method security
```java
@EnableMethodSecurity   // on a @Configuration class

@PreAuthorize("hasAuthority('SCOPE_cert:revoke')")
public void revoke(String serial) { ... }

@PreAuthorize("hasRole('ADMIN') or #ownerId == authentication.name")  // SpEL, resource ownership
public Account get(String ownerId) { ... }

@PostAuthorize("returnObject.orgId == authentication.principal.orgId") // check the result
public Server load(String id) { ... }

@PreFilter / @PostFilter   // filter collection args/returns by element
```
`@PreAuthorize` runs **before** the method (most common); `@PostAuthorize` after (when the decision depends on the returned object). These use SpEL with security context.

### 7. Token relay between services
In a microservice call chain, the incoming token must be **forwarded** to downstream services (so they can authorize). Spring Security's OAuth2 client / `WebClient` token relay, or simply propagating the `Authorization` header, handles this. cent's gateway authenticates, then downstream services re-validate the token (defense in depth).

---

## PRACTICE

```java
// Map JWT scope + custom "roles" claim to Spring authorities
@Bean
JwtAuthenticationConverter customConverter() {
    JwtGrantedAuthoritiesConverter scopes = new JwtGrantedAuthoritiesConverter();   // SCOPE_*
    JwtAuthenticationConverter conv = new JwtAuthenticationConverter();
    conv.setJwtGrantedAuthoritiesConverter(jwt -> {
        var auth = new ArrayList<GrantedAuthority>(scopes.convert(jwt));
        List<String> roles = jwt.getClaimAsStringList("roles");
        if (roles != null) roles.forEach(r -> auth.add(new SimpleGrantedAuthority("ROLE_" + r)));
        return auth;
    });
    return conv;
}

@RestController
@RequestMapping("/api/certs")
class CertController {
    @PreAuthorize("hasAuthority('SCOPE_cert:revoke')")
    @PostMapping("/{serial}/revoke")
    public void revoke(@PathVariable String serial,
                       @AuthenticationPrincipal Jwt jwt) {
        String org = jwt.getClaimAsString("org_id");   // claims from the validated token
        // ... revoke for that org
    }
}

// Service-to-service: Client Credentials (no user) — cent's CLIENT_CREDENTIALS mode
RestClient client = RestClient.create();
JamfToken token = client.post()
    .uri("https://jamf.example.com/api/oauth/token")
    .body(Map.of("grant_type", "client_credentials",
                 "client_id", clientId, "client_secret", clientSecret))
    .retrieve().body(JamfToken.class);
```

**Exercises:**
1. Stand up a resource server with `issuer-uri`; call an endpoint with/without a valid bearer token (401 vs 200).
2. Decode a JWT at jwt.io (or Base64-decode the payload) and identify `sub`, `exp`, `scope` — prove it's readable (not encrypted).
3. Add `@PreAuthorize` with a SpEL ownership check (`#ownerId == authentication.name`).
4. Design (in writing) a revocation strategy for a "logout" feature given stateless JWTs.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Is a JWT encrypted? Can you put a password or PII in it?**
A standard JWT is **signed, not encrypted** (JWS) — the payload is just Base64URL-encoded and **anyone can read it**. The signature guarantees **integrity** (not tampered) and **authenticity** (from the trusted issuer), not confidentiality. So **never** put secrets/passwords/sensitive PII in a JWT. If you need confidentiality, use **JWE** (encrypted JWT), which is separate and less common.

**Q2. How does a resource server validate a JWT without calling the auth server per request?**
For RS256, it fetches the issuer's **public keys from the JWKS endpoint** (discovered via `issuer-uri`/well-known config) and **caches** them, then verifies each token's **signature** locally, plus checks `exp`, `iss`, `aud`, `nbf`. This is **stateless and fast** — no per-request network/DB lookup. It only refetches JWKS on key rotation. (Opaque tokens, by contrast, require introspection calls.)

**Q3. The hardest JWT question: how do you revoke a JWT before it expires?**
You fundamentally **can't** with pure stateless JWTs — they're valid until `exp`. Practical mitigations: **short-lived access tokens (minutes) + revocable refresh tokens** (so the blast radius is small), a **denylist of revoked `jti`** checked per request (adds some state but only for revoked tokens), or a **per-user token version/"tokens-valid-after" timestamp** that invalidates all older tokens. It's an inherent **statelessness vs immediate-revocation trade-off**; most systems pick short TTL + refresh.

**Q4. `@PreAuthorize` vs `@PostAuthorize` — when each?**
`@PreAuthorize` evaluates **before** the method runs — use it for the common case (gate by role/scope/args). `@PostAuthorize` evaluates **after**, with access to `returnObject` — use it when the decision depends on the **result** (e.g., "you can read this server only if it belongs to your org," which you can't know until you've loaded it). Note `@PostAuthorize` still **executes** the method (and any side effects) before denying, so don't use it for state-changing methods.

**Q5. Authorization Code + PKCE vs Client Credentials — when each?**
**Authorization Code (with PKCE)** is for flows involving a **user** logging in (web/mobile/SPA); PKCE protects public clients that can't keep a secret. **Client Credentials** is for **service-to-service** calls with **no user** — the service authenticates as itself. cent's Jamf integration switches between a user/basic flow and `CLIENT_CREDENTIALS` for machine-to-machine token acquisition, which is exactly this distinction.

**Q6. Access token vs refresh token?**
The **access token** is short-lived, sent on every API call, and grants resource access (often a JWT validated statelessly). The **refresh token** is long-lived, kept secret by the client, and used **only** against the auth server to obtain new access tokens **without re-login**. Refresh tokens are **revocable/server-tracked**, which is how you reconcile JWT statelessness with the ability to cut off access (revoke the refresh token → no new access tokens).

**Q7. In a call chain A→B→C, how does C know who the user is?**
Via **token relay**: A forwards the incoming bearer token (Authorization header) to B, which forwards to C; each service **re-validates** the token and authorizes independently (defense in depth — never trust that an upstream already checked). Spring Security's OAuth2 client/`WebClient` token-relay filter automates this. The gateway authenticates at the edge, but downstream services still validate — exactly cent's model.

**Q8. Why disable CSRF and use STATELESS sessions for a JWT API?**
JWTs are sent in the **Authorization header**, not auto-attached cookies, so the CSRF attack vector (browser silently sending ambient cookies) doesn't apply → CSRF protection is unnecessary overhead. STATELESS tells Spring not to create/use an `HttpSession`, so no server-side session state exists — each request stands alone via its token, enabling horizontal scaling without sticky sessions or a shared session store.

➡ Next: [Day 19 — Microservices & Spring Cloud Config](day-19-microservices-config-server.md)
