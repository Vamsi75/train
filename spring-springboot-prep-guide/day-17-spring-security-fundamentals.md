# Day 17 — Spring Security Fundamentals

## THEORY

### 1. The security filter chain (the mental model)
Spring Security is a **chain of servlet filters** (`FilterChainProxy` → `SecurityFilterChain`) that runs **before** your controllers. Each filter has a job; the request passes through them in order:
- `SecurityContextPersistenceFilter` / `SecurityContextHolderFilter` — load/store the `SecurityContext`.
- `CsrfFilter` — CSRF protection.
- Authentication filters (`UsernamePasswordAuthenticationFilter`, `BearerTokenAuthenticationFilter`, etc.).
- `ExceptionTranslationFilter` — turns auth exceptions into 401/403 or redirects.
- `AuthorizationFilter` — enforces access rules.
Understanding "it's a filter chain" answers most "where does X happen" questions.

### 2. Authentication vs Authorization
- **Authentication (authN):** *who are you?* — verify identity (credentials, token).
- **Authorization (authZ):** *what may you do?* — check roles/authorities/permissions.
The result of authN is an **`Authentication`** object stored in the **`SecurityContextHolder`** (thread-local); authZ reads it.

### 3. Core abstractions
- **`Authentication`** — principal + credentials + authorities; the "who".
- **`SecurityContextHolder`** — holds the current `Authentication` (thread-local by default).
- **`UserDetailsService`** — loads user data by username (`loadUserByUsername`).
- **`UserDetails`** — the user model (username, password, authorities, flags).
- **`AuthenticationManager`/`ProviderManager`** — orchestrates authentication via `AuthenticationProvider`s.
- **`PasswordEncoder`** — hashes/verifies passwords.
- **`GrantedAuthority`** — a permission/role.

### 4. Modern config (Spring Security 6 — component-based, no `WebSecurityConfigurerAdapter`)
`WebSecurityConfigurerAdapter` was **removed**. You now declare a `SecurityFilterChain` bean:
```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity                  // enables @PreAuthorize etc.
public class SecurityConfig {

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
          .authorizeHttpRequests(auth -> auth
              .requestMatchers("/actuator/health", "/public/**").permitAll()
              .requestMatchers("/api/admin/**").hasRole("ADMIN")
              .requestMatchers(HttpMethod.GET, "/api/**").hasAuthority("SCOPE_read")
              .anyRequest().authenticated())
          .csrf(csrf -> csrf.disable())          // disable for stateless APIs (see Q)
          .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
          .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()));  // Day 18
        return http.build();
    }

    @Bean
    PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }
}
```

### 5. Password encoding
Never store plaintext or fast hashes. Use **BCrypt** (default), or `DelegatingPasswordEncoder` (`{bcrypt}...`, `{argon2}...`) which supports **multiple algorithms with a prefix**, enabling seamless migration. BCrypt is adaptive (work factor) and salted automatically.

### 6. Roles vs authorities
A **role** is just an authority with the `ROLE_` prefix convention. `hasRole("ADMIN")` checks authority `ROLE_ADMIN`; `hasAuthority("ROLE_ADMIN")` is the explicit form. OAuth2 scopes map to `SCOPE_*` authorities.

### 7. CSRF & CORS (commonly confused)
- **CSRF** (Cross-Site Request Forgery): a malicious site tricks a logged-in browser into making a state-changing request using its cookies. Protection = a token the attacker can't read. **Relevant for cookie/session auth; typically disabled for stateless token (JWT) APIs** since there's no ambient cookie to abuse.
- **CORS** (Cross-Origin Resource Sharing): browser policy controlling which origins may call your API from JS. Configure allowed origins/methods/headers — **not** a substitute for auth, it's a browser-enforced rule.

### 8. Stateless vs session
- **Session-based:** server stores session; browser holds `JSESSIONID` cookie. Stateful, needs sticky sessions or shared session store across replicas.
- **Stateless (token/JWT):** no server session; the token carries identity each request — scales horizontally with no shared state (the right choice for microservices like cent).

---

## PRACTICE

```java
// In-memory users for learning (NOT production)
@Bean
UserDetailsService users(PasswordEncoder encoder) {
    UserDetails admin = User.withUsername("admin")
        .password(encoder.encode("admin123")).roles("ADMIN", "USER").build();
    UserDetails user = User.withUsername("user")
        .password(encoder.encode("user123")).roles("USER").build();
    return new InMemoryUserDetailsManager(admin, user);
}

// Production-style: load from DB
@Service
class DbUserDetailsService implements UserDetailsService {
    private final AppUserRepository repo;
    DbUserDetailsService(AppUserRepository repo) { this.repo = repo; }
    public UserDetails loadUserByUsername(String username) {
        AppUser u = repo.findByUsername(username)
            .orElseThrow(() -> new UsernameNotFoundException(username));
        return User.withUsername(u.getUsername())
                   .password(u.getPasswordHash())          // already BCrypt-encoded
                   .authorities(u.getAuthorities().toArray(String[]::new))
                   .build();
    }
}

// Reading the current user
@GetMapping("/me")
public String me(@AuthenticationPrincipal UserDetails principal) {
    return principal.getUsername();
    // or: SecurityContextHolder.getContext().getAuthentication()
}
```

**Exercises:**
1. Secure an app with two in-memory users; lock `/api/admin/**` to `ADMIN` and confirm 403 for a normal user.
2. Implement a DB-backed `UserDetailsService` with BCrypt-hashed passwords.
3. Disable CSRF + set `STATELESS` and explain why that's appropriate for a token API.
4. Inject `@AuthenticationPrincipal` and return the caller's username.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. How does a request flow through Spring Security?**
Before reaching controllers, the request passes through the **`FilterChainProxy`**, which delegates to a matching **`SecurityFilterChain`** — an ordered list of filters. Filters load the `SecurityContext`, perform CSRF checks, attempt authentication (extracting credentials/tokens and building an `Authentication`), then the `AuthorizationFilter` enforces access rules; `ExceptionTranslationFilter` converts auth failures into 401/403. If all pass, the request proceeds to the controller. It's fundamentally a **filter chain**, not magic.

**Q2. Authentication vs Authorization — and where is the result stored?**
**Authentication** verifies *identity* (who you are); **Authorization** verifies *permissions* (what you can do). Authentication produces an `Authentication` object stored in the **`SecurityContextHolder`** (a thread-local by default). Authorization (URL rules, `@PreAuthorize`) reads that object's authorities to allow/deny. AuthN happens first; authZ uses its result.

**Q3. `WebSecurityConfigurerAdapter` is gone — how do you configure security now?**
In Spring Security 6 you declare beans: a **`SecurityFilterChain`** bean built from `HttpSecurity` (the component-based model), plus beans like `PasswordEncoder`, `UserDetailsService`, and (for method security) `@EnableMethodSecurity`. The lambda DSL (`authorizeHttpRequests(auth -> ...)`) replaces the old override methods. This makes config explicit, composable (multiple filter chains), and testable.

**Q4. CSRF vs CORS — and should you disable CSRF for a REST API?**
**CSRF** defends against a browser being tricked into sending state-changing requests using its **ambient cookies**; **CORS** is a browser rule about which **origins** may call your API from JavaScript. For a **stateless token (JWT) API**, there's no session cookie to abuse, so CSRF protection is commonly **disabled** (the token isn't sent automatically by the browser). For **cookie/session-based** apps, **keep CSRF on**. CORS still must be configured correctly regardless — it's not a security control by itself, just a browser policy.

**Q5. Why BCrypt (or Argon2) and not SHA-256 for passwords?**
Password hashes must be **slow and salted** to resist brute force. SHA-256 is **fast and unsalted** — GPUs test billions/sec and identical passwords yield identical hashes (rainbow tables). **BCrypt/Argon2/scrypt** are **adaptive** (tunable work factor) and salt automatically, making large-scale cracking infeasible. Spring's `DelegatingPasswordEncoder` stores an algorithm prefix (`{bcrypt}`) so you can upgrade algorithms over time without breaking existing hashes.

**Q6. Role vs authority in Spring Security?**
A **role is just an authority with the `ROLE_` prefix** by convention. `hasRole("ADMIN")` is shorthand for checking the `ROLE_ADMIN` authority; `hasAuthority("ROLE_ADMIN")` is the explicit equivalent. Fine-grained permissions are usually modeled as plain authorities (e.g., `cert:revoke`), and OAuth2 scopes appear as `SCOPE_*` authorities. Don't double-prefix (`hasRole("ROLE_ADMIN")` looks for `ROLE_ROLE_ADMIN`).

**Q7. Stateless vs session-based auth for microservices — which and why?**
**Stateless (token/JWT)** for microservices: each request carries its own identity, so any replica can serve it with **no shared session store and no sticky sessions** — horizontally scalable, which matters in a fleet like cent. **Session-based** keeps state on the server (or a shared store like Redis), simpler for traditional server-rendered apps but adds coordination overhead across replicas. The trade-off with JWT is revocation difficulty (Day 18).

**Q8. How do you get the current user inside a service (not a controller)?**
Read `SecurityContextHolder.getContext().getAuthentication()` (thread-local). In controllers, `@AuthenticationPrincipal` or an `Authentication`/`Principal` parameter is cleaner. Caveat: the context is **thread-bound**, so in `@Async`/reactive flows it doesn't propagate automatically — you need `DelegatingSecurityContextExecutor` (MVC async) or `ReactiveSecurityContextHolder` (WebFlux).

➡ Next: [Day 18 — JWT, OAuth2 & Method Security](day-18-jwt-oauth2-resource-server.md)
