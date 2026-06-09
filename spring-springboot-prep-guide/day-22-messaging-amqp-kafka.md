# Day 22 — Messaging: Spring AMQP (RabbitMQ) & Kafka

> cent services communicate over **AMQP** (you saw `IAMQPEnabledRestController` and `transport.messaging`). This day is directly relevant.

## THEORY

### 1. Why asynchronous messaging?
Synchronous REST couples services in time (both must be up; caller waits). **Messaging** decouples them:
- **Temporal decoupling** — producer doesn't wait; consumer processes when ready (and can be down temporarily — the broker buffers).
- **Load leveling** — a queue absorbs spikes; consumers drain at their pace.
- **Fan-out** — one event, many independent consumers.
- **Resilience** — if a consumer is down, messages wait instead of being lost.
Trade-off: **eventual consistency**, ordering concerns, and more moving parts.

### 2. RabbitMQ / AMQP model
- **Producer** → **Exchange** → (bindings/routing) → **Queue(s)** → **Consumer**.
- The **exchange** decides routing; queues hold messages; bindings connect them.
- Exchange types: **direct** (route by exact routing key), **topic** (wildcard routing keys, e.g., `cert.revoked.*`), **fanout** (broadcast to all bound queues), **headers**.
- **Acknowledgments**: a consumer acks a message after processing; un-acked messages are redelivered (at-least-once). Manual ack gives you control over when "done" means done.

### 3. Spring AMQP essentials
```java
@Configuration
class AmqpConfig {
    @Bean TopicExchange certExchange() { return new TopicExchange("cert.events"); }
    @Bean Queue revokedQueue()         { return QueueBuilder.durable("cert.revoked.q").build(); }
    @Bean Binding binding(Queue revokedQueue, TopicExchange certExchange) {
        return BindingBuilder.bind(revokedQueue).to(certExchange).with("cert.revoked.#");
    }
    @Bean Jackson2JsonMessageConverter converter() { return new Jackson2JsonMessageConverter(); }
}

// Produce
@Service
class CertEventPublisher {
    private final RabbitTemplate rabbit;
    CertEventPublisher(RabbitTemplate rabbit) { this.rabbit = rabbit; }
    public void publishRevoked(CertRevokedEvent e) {
        rabbit.convertAndSend("cert.events", "cert.revoked.manual", e);
    }
}

// Consume
@Component
class CertEventListener {
    @RabbitListener(queues = "cert.revoked.q")
    public void onRevoked(CertRevokedEvent e) {
        // idempotent processing!
    }
}
```

### 4. Kafka model (different beast)
- **Topic** partitioned into **partitions**; messages are an **append-only log** retained for a configured time (not deleted on consume).
- **Consumers** in a **consumer group** each read a subset of partitions; **offset** tracks position. Consumers can **replay** by resetting offsets.
- **Ordering** is guaranteed **within a partition** (keyed by a partition key), not across the topic.
- Built for **high-throughput streaming, event sourcing, and replayable logs**.
```java
@KafkaListener(topics = "cert-events", groupId = "notifier")
public void consume(CertRevokedEvent e) { ... }
// kafkaTemplate.send("cert-events", key, event);
```

### 5. RabbitMQ vs Kafka (the comparison interviewers want)
| | RabbitMQ (AMQP) | Kafka |
|--|-----------------|-------|
| Model | Smart broker, queues, routing | Distributed log, partitions |
| Message after consume | Removed (acked) | **Retained** (replayable) |
| Ordering | Per-queue | Per-partition |
| Throughput | High | **Very high** (log-structured) |
| Routing | Rich (exchanges/bindings) | Simple (topic+key) |
| Best for | Task queues, RPC, complex routing, per-message workflows | Event streaming, event sourcing, high-volume pipelines, replay |
RabbitMQ = "smart broker, dumb consumer"; Kafka = "dumb broker (log), smart consumer (tracks offset)".

### 6. Delivery guarantees & idempotency
- **At-most-once** (fire and forget — may lose), **at-least-once** (default; may **duplicate** → consumers must be **idempotent**), **exactly-once** (hard; Kafka offers transactional/EOS within Kafka, but end-to-end EOS usually means **at-least-once + idempotent consumer**).
- **Always design consumers to be idempotent** (dedupe by message id / business key) because redelivery happens.

### 7. Dead Letter Queues (DLQ) & poison messages
A message that repeatedly fails processing (a "poison message") shouldn't be retried forever (it blocks the queue). Route it to a **Dead Letter Queue** after N attempts for inspection/manual handling. Configure DLX (dead-letter exchange) in RabbitMQ or a DLT (dead-letter topic) in Spring Kafka.

### 8. Transactional messaging & the outbox pattern
Publishing an event and committing a DB change must not diverge (you don't want "DB saved but event lost" or vice versa). The **Transactional Outbox**: within the DB transaction, write the event to an `outbox` table; a separate process/CDC publishes it to the broker. This guarantees the event is published iff the DB change committed — solving the **dual-write** problem.

---

## PRACTICE

```java
// Idempotent consumer with manual ack + DLQ routing
@Configuration
class QueueConfig {
    @Bean Queue work() {
        return QueueBuilder.durable("cert.work.q")
            .withArgument("x-dead-letter-exchange", "cert.dlx")   // failed msgs → DLQ
            .build();
    }
    @Bean Queue dlq() { return QueueBuilder.durable("cert.work.dlq").build(); }
}

@Component
class WorkListener {
    private final ProcessedRepo processed;   // dedupe store
    WorkListener(ProcessedRepo processed) { this.processed = processed; }

    @RabbitListener(queues = "cert.work.q")
    public void handle(CertJob job) {
        if (processed.existsById(job.id())) return;   // idempotency: skip duplicates
        // ... do the work ...
        processed.save(new Processed(job.id()));
    }
}
```
```java
// Outbox: publish event in the SAME transaction as the business change
@Transactional
public void revoke(String serial) {
    certRepo.markRevoked(serial);                       // business change
    outboxRepo.save(new OutboxEvent("cert.revoked", serial));  // event row, same tx
    // a relay polls outbox → publishes to broker → marks sent
}
```

**Exercises:**
1. Set up a topic exchange + queue + binding; publish with a routing key and consume it.
2. Make a consumer idempotent (dedupe by message id); redeliver the same message and prove it's processed once.
3. Configure a DLQ; throw repeatedly in the listener and watch the poison message land in the DLQ.
4. Implement a minimal outbox: write event + business change in one transaction; describe how a relay publishes it.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. RabbitMQ vs Kafka — when do you choose each?**
**RabbitMQ** (smart broker): rich routing (exchanges/bindings), per-message workflows, task queues, RPC, lower-volume with complex delivery logic; messages are **removed once acked**. **Kafka** (distributed log): very high throughput, **retained/replayable** event streams, event sourcing, multiple independent consumer groups reading the same data, ordering per partition. Rule of thumb: **task/command queues with routing → RabbitMQ; high-volume event streaming/replay → Kafka.** (cent uses AMQP/RabbitMQ for service messaging.)

**Q2. What delivery guarantee do you usually get, and what must consumers do about it?**
Typically **at-least-once** — the broker redelivers if it doesn't get an ack (e.g., consumer crashed mid-processing), so **duplicates happen**. Therefore consumers **must be idempotent**: dedupe by a message/business id, or make the operation naturally idempotent (upsert, set-state). "Exactly-once" end-to-end is largely a myth in practice; the standard pattern is **at-least-once + idempotent consumer**.

**Q3. Why is "exactly-once" delivery so hard?**
Because of failures between **processing** and **acknowledging**: if a consumer processes a message then crashes before acking, the broker redelivers (duplicate); if it acks before processing and then crashes, the message is lost. You can't atomically "process + ack + side-effect" across a network without distributed transactions, which are expensive/limited. Kafka offers transactional EOS *within Kafka*, but as soon as you touch an external DB you're back to at-least-once + idempotency.

**Q4. What is a poison message and how do you handle it?**
A message that **repeatedly fails** processing (bad payload, bug) — if retried indefinitely it **blocks the queue** and wastes resources. Handle it with a **retry limit** then route to a **Dead Letter Queue/Topic (DLQ/DLT)** for inspection, alerting, and manual or automated remediation. This isolates the bad message so good ones keep flowing.

**Q5. The dual-write problem and the outbox pattern — explain.**
**Dual write:** you must update the DB *and* publish an event. If you do them as two separate operations, a crash between them leaves them **inconsistent** (DB changed but event lost, or event sent but DB rolled back). The **Transactional Outbox** writes the event into an `outbox` table **inside the same DB transaction** as the business change (so they commit atomically); a **separate relay** (poller or CDC like Debezium) reads the outbox and publishes to the broker, marking rows sent. The event is published **iff** the DB change committed.

**Q6. How does message ordering work in Kafka vs RabbitMQ?**
**Kafka** guarantees ordering **within a partition** only — messages with the same **key** go to the same partition and stay ordered; across partitions there's no global order, which is the price of parallelism. **RabbitMQ** preserves order **within a single queue** with a single consumer, but multiple consumers/competing-consumers or requeue-on-failure can reorder. If strict ordering matters, use a partition key (Kafka) or a single consumer per ordering-scope (Rabbit), accepting reduced parallelism.

**Q7. Synchronous REST vs asynchronous messaging — how do you decide?**
Use **synchronous REST** when the caller **needs an immediate response** and the operation is request/response (queries, user-facing reads). Use **async messaging** when you want **temporal decoupling, load leveling, fan-out, or resilience** — fire-and-forget commands, domain events, long-running work, or when the consumer may be temporarily down. Messaging trades immediate consistency for decoupling and scalability; many systems use both (REST for queries, events for state propagation).

**Q8. Manual vs automatic acknowledgment — why does it matter?**
With **auto-ack**, the broker considers a message delivered as soon as it's sent to the consumer — if the consumer crashes mid-processing, the message is **lost**. With **manual ack**, the consumer acks **only after successful processing**, so a crash before ack triggers **redelivery** (at-least-once). Manual ack (plus idempotency and prefetch limits) is the correct choice for work you can't afford to lose; the cost is handling duplicates and managing prefetch to avoid one consumer hoarding messages.

➡ Next: [Day 23 — Testing](day-23-testing.md)
