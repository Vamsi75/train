# Day 0 — Environment Setup

## Prerequisites
- **JDK 17 or 21** (LTS). Verify: `java -version`. Spring Boot 3.x requires Java 17+.
- **Maven 3.6+** (or Gradle). Verify: `mvn -version`.
- An IDE: **IntelliJ IDEA** (best Spring support) or VS Code + Java/Spring extensions.

## Generate a starter project
Use [start.spring.io](https://start.spring.io) (Spring Initializr) — the canonical way to bootstrap.
- Project: **Maven**, Language: **Java**, Spring Boot: **3.2.x+ (stable, not SNAPSHOT)**.
- Group: `com.example`, Artifact: `demo`, Packaging: **Jar**, Java: **17/21**.
- Dependencies to start: **Spring Web**, **Spring Boot Actuator**, **Lombok** (optional), **Spring Boot DevTools**.

Or via CLI:
```bash
curl https://start.spring.io/starter.zip \
  -d dependencies=web,actuator,data-jpa,validation \
  -d javaVersion=21 -d bootVersion=3.2.5 \
  -d type=maven-project -d name=demo -o demo.zip
unzip demo.zip -d demo
```

## Anatomy of a Spring Boot project
```
demo/
├── pom.xml                         # dependencies, parent = spring-boot-starter-parent
├── src/main/java/com/example/demo/
│   └── DemoApplication.java        # @SpringBootApplication + main()
├── src/main/resources/
│   ├── application.yml             # configuration
│   ├── static/                     # static web assets
│   └── templates/                  # server-side templates
└── src/test/java/...               # tests
```

## The entry point
```java
@SpringBootApplication
public class DemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
```

## Run it
```bash
./mvnw spring-boot:run        # dev
./mvnw clean package          # build fat jar → target/demo-0.0.1-SNAPSHOT.jar
java -jar target/demo-*.jar   # run the jar
```
Hit `http://localhost:8080/actuator/health` → should return `{"status":"UP"}`.

## How the cent platform is structured (real-world reference)
Centurion is a **multi-module Maven monorepo** of microservices:
- A **BOM** (`bom/pom.xml`) centralizes dependency versions so every service aligns.
- Each service is its own Spring Boot app (e.g., `aaa-server-management-service`, `api-gateway-service`, `authentication-portal-service`).
- A **Spring Cloud Config Server** serves per-service YAML from `infrastructure/spring-cloud/configuration-server/config/<service>.yml`.
- Services talk over REST **and** AMQP (RabbitMQ) messaging.
We'll mirror these patterns as we go, so the concepts map onto something real.

## A note on `jakarta.*` vs `javax.*`
Spring Boot 3 moved to **Jakarta EE 9+**, so imports are `jakarta.persistence.*`, `jakarta.validation.*`, `jakarta.servlet.*` — **not** `javax.*`. This is the #1 gotcha when upgrading from Boot 2.x. All examples here use `jakarta.*`.

You're ready. Go to [Day 01](../day-01-spring-overview-ioc-di.md).
