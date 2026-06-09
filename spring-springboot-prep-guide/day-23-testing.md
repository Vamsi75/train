# Day 23 — Testing: Unit, Slice, Integration & Testcontainers

## THEORY

### 1. The test pyramid
- **Many unit tests** (fast, no Spring) — pure logic, mocked collaborators.
- **Fewer slice/integration tests** (load part of the context) — controllers, repos, security.
- **Few end-to-end tests** (whole app + real dependencies) — slow, brittle, high value.
Invert it (too many slow E2E tests) and your suite becomes slow and flaky.

### 2. Plain unit tests (no Spring) — why constructor injection pays off
```java
class OrderServiceTest {
    @Test void appliesDiscount() {
        var repo = mock(OrderRepo.class);                 // Mockito
        var service = new OrderService(repo);             // no Spring context!
        when(repo.findById(1L)).thenReturn(Optional.of(new Order(...)));
        assertThat(service.total(1L)).isEqualByComparingTo("90.00");
        verify(repo).findById(1L);
    }
}
```
Because dependencies come through the constructor, you instantiate the class directly with mocks — **milliseconds, no container**. (Field injection forces reflection/`@SpringBootTest`.)

### 3. Mockito essentials
`mock()`, `when(...).thenReturn(...)`, `thenThrow`, `verify(mock, times(n))`, `ArgumentCaptor`, `@Mock`/`@InjectMocks` (with `@ExtendWith(MockitoExtension.class)`), `@Spy` (partial mock). **Stub queries, verify commands.** Don't over-verify (testing implementation, not behavior).

### 4. Slice tests (load only what you need — fast)
| Annotation | Loads | For testing |
|------------|-------|-------------|
| `@WebMvcTest(XController.class)` | MVC layer only (controllers, filters, advice) | Controllers + serialization + validation, with **`MockMvc`**; mock the service via `@MockBean`. |
| `@DataJpaTest` | JPA layer (repos, entities, in-memory/Testcontainers DB) | Repository queries; transactional + rolled back per test. |
| `@JsonTest` | Jackson | Serialization. |
| `@RestClientTest` | REST clients | Outbound HTTP with `MockRestServiceServer`. |
| `@WebFluxTest` | WebFlux | Reactive controllers with `WebTestClient`. |

```java
@WebMvcTest(ServerController.class)
class ServerControllerTest {
    @Autowired MockMvc mvc;
    @MockBean ServerService service;          // mock the collaborator

    @Test void returns404WhenMissing() throws Exception {
        when(service.find("x")).thenReturn(Optional.empty());
        mvc.perform(get("/api/v1/servers/x"))
           .andExpect(status().isNotFound());
    }
}
```

### 5. Full integration tests
```java
@SpringBootTest(webEnvironment = RANDOM_PORT)   // whole context + embedded server
class ServerApiIT {
    @Autowired TestRestTemplate rest;           // or WebTestClient
    @Test void createsServer() {
        var res = rest.postForEntity("/api/v1/servers", new CreateServerRequest(...), ServerDto.class);
        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }
}
```
`@SpringBootTest` loads the **entire** context — powerful but slow; use sparingly. The context is **cached and reused** across tests with the same configuration (key performance lever).

### 6. Testcontainers — real dependencies in Docker
Instead of H2 (which behaves differently from prod), spin up the **real database/broker** in a container for tests — catching dialect/behavior bugs H2 hides.
```java
@SpringBootTest
@Testcontainers
class RepoIT {
    @Container @ServiceConnection                       // Boot 3.1+ auto-wires the datasource
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0");

    @Autowired AAAServerRepository repo;
    @Test void persists() { assertThat(repo.save(new AAAServer(...)).getId()).isNotNull(); }
}
```
`@ServiceConnection` (Boot 3.1+) auto-configures Spring to use the container — no manual `@DynamicPropertySource`.

### 7. Test config & profiles
- `@ActiveProfiles("test")`, `@TestPropertySource`, `application-test.yml`.
- `@MockBean`/`@SpyBean` replace beans in the context (note: each unique combination creates a **new context**, slowing tests — minimize variety).
- Security in tests: `@WithMockUser`, `spring-security-test` MockMvc helpers.

### 8. What to test where
- **Logic & edge cases** → unit tests.
- **Serialization/validation/routing/status codes** → `@WebMvcTest`.
- **Query correctness** → `@DataJpaTest` + Testcontainers.
- **Wiring + critical happy paths** → a few `@SpringBootTest`.

---

## PRACTICE

```java
// Mockito with annotations
@ExtendWith(MockitoExtension.class)
class RevocationServiceTest {
    @Mock CertRepo repo;
    @Mock ApplicationEventPublisher publisher;
    @InjectMocks RevocationService service;

    @Test void publishesEventOnRevoke() {
        service.revoke("ABC123");
        var captor = ArgumentCaptor.forClass(CertRevokedEvent.class);
        verify(publisher).publishEvent(captor.capture());
        assertThat(captor.getValue().serial()).isEqualTo("ABC123");
    }
}

// Security-aware controller slice test
@WebMvcTest(CertController.class)
class CertControllerSecurityTest {
    @Autowired MockMvc mvc; @MockBean CertService service;

    @Test @WithMockUser(authorities = "SCOPE_cert:revoke")
    void allowsAuthorized() throws Exception {
        mvc.perform(post("/api/certs/ABC/revoke").with(csrf())).andExpect(status().isOk());
    }
    @Test @WithMockUser(authorities = "SCOPE_read")
    void forbidsUnauthorized() throws Exception {
        mvc.perform(post("/api/certs/ABC/revoke").with(csrf())).andExpect(status().isForbidden());
    }
}
```

**Exercises:**
1. Write a pure unit test for a service using Mockito (no Spring); use `ArgumentCaptor` to assert on a published event.
2. `@WebMvcTest` a controller: assert 201 on create, 404 on missing, 400 on invalid body — with `@MockBean` service.
3. `@DataJpaTest` + Testcontainers MySQL: write a derived query and assert it returns the right rows against a *real* DB.
4. Add `@WithMockUser` tests proving an endpoint is allowed for one authority and forbidden for another.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. `@SpringBootTest` vs `@WebMvcTest` vs `@DataJpaTest` — when each?**
`@SpringBootTest` loads the **entire** application context (+ optionally an embedded server) → full integration tests; powerful but **slow**, use for a few critical paths. `@WebMvcTest` loads **only the web layer** (controllers, advice, filters) with `MockMvc` and mocked services → fast controller tests (routing, validation, status codes, serialization). `@DataJpaTest` loads **only the JPA layer** with a test DB, transactional and rolled back per test → repository/query tests. Slices keep tests fast by loading the minimum.

**Q2. Why does constructor injection make unit testing easier?**
You can instantiate the class with `new Service(mockDep1, mockDep2)` and test it **without any Spring context** — fast and isolated. With **field injection**, the fields are private and set by reflection, so you can't easily supply mocks without a container or reflection hacks (`ReflectionTestUtils`), forcing slower `@SpringBootTest`-style tests. Constructor injection makes dependencies explicit and the class trivially testable.

**Q3. Why Testcontainers over H2 for repository tests?**
H2 is a **different database** with a different SQL dialect/behavior, so tests can pass on H2 but the same query **fails on the real MySQL/Postgres in production** (functions, types, locking, JSON, sequences, case sensitivity). **Testcontainers** runs the **actual database engine in Docker**, so your tests exercise real dialect and behavior — catching dialect bugs before prod. Boot 3.1's `@ServiceConnection` makes wiring trivial. The cost is Docker + slower startup (mitigated by container reuse).

**Q4. `@Mock` vs `@MockBean` — what's the difference?**
`@Mock` (Mockito) creates a mock object for a **plain unit test** — no Spring involved. `@MockBean` (Spring Boot Test) creates a mock **and puts it in the Spring application context**, replacing the real bean — for slice/integration tests where the context is loaded and you want to mock one collaborator. Overusing `@MockBean` with many different combinations **fragments the context cache** (each unique set spawns a new context), slowing the suite.

**Q5. Why is the Spring context cached between tests, and how do you avoid blowing the cache?**
Loading the context is expensive, so Spring **caches and reuses** it across test classes that share the **same configuration**. Anything that changes the configuration — different `@MockBean`s, `@TestPropertySource`, `@ActiveProfiles`, `@DirtiesContext` — creates a **new** context, ballooning total test time. Keep test configurations **consistent**, avoid `@DirtiesContext` unless necessary, and standardize mock sets so the cache is reused.

**Q6. What should you mock and what should you not?**
**Mock** external/slow collaborators you don't own or that have side effects: remote clients, repositories (in service unit tests), message brokers, the clock/randomness. **Don't mock** value objects/DTOs, the class under test, or types you don't own in a way that **couples to their internals** (mocking third-party APIs you don't understand leads to tests that pass while prod fails). Prefer testing **behavior** (outputs/interactions that matter), not implementation details.

**Q7. How do you test secured endpoints?**
Use `spring-security-test`: `@WithMockUser(authorities=...)`/`@WithMockUser(roles=...)` to set an authenticated principal, and the MockMvc request post-processors (`with(csrf())`, `with(jwt())`, `with(user(...))`). Write tests asserting **both** the allowed case (correct authority → 2xx) and the denied case (wrong/missing authority → 401/403). For JWT resource servers, `SecurityMockMvcRequestPostProcessors.jwt()` injects a mock token with chosen claims/scopes.

**Q8. Your integration test suite is slow and flaky. What do you do?**
Rebalance toward the **pyramid**: push logic into fast **unit tests**, use **slice tests** instead of full `@SpringBootTest` where possible, and reserve full integration/E2E for a few critical flows. **Reuse the context cache** (consistent config, fewer `@MockBean` variants, avoid `@DirtiesContext`). Make tests **deterministic** (control the clock, avoid real sleeps/time-dependence, use Testcontainers with fixed images, await conditions instead of `Thread.sleep`). Parallelize where safe.

➡ Next: [Day 24 — Reactive Programming & WebFlux](day-24-reactive-webflux.md)
