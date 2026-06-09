# Day 21 — High Availability, Failover & Clustering

## THEORY

### 1. What HA means
Keep the database **available** despite failures (server crash, disk failure, network partition, AZ outage). Measured in "nines" (99.9% ≈ 8.7h downtime/yr; 99.99% ≈ 52min/yr). HA = redundancy + automatic failover + no/low data loss.

### 2. HA building blocks
- **Redundancy** — more than one copy of the data on more than one machine (replication).
- **Failure detection** — health checks / heartbeats to notice the primary is down.
- **Failover** — promote a replica to primary automatically.
- **Traffic redirection** — point the app at the new primary (VIP, DNS, proxy, or service discovery) without code changes.
- **Fencing / STONITH** — ensure the old primary can't keep accepting writes ("split-brain" prevention).

### 3. Common MySQL HA architectures
1. **Async/semi-sync replication + orchestrator/MHA**
   - One primary, replicas; an external tool (**Orchestrator**, MHA) detects failure and promotes a replica.
   - Pros: simple, flexible. Cons: async = possible data loss; failover logic is bolted on.
2. **MySQL InnoDB Cluster (Group Replication + MySQL Router + MySQL Shell/AdminAPI)**
   - **Group Replication**: a set of servers forming a group with Paxos-based consensus; (virtually) synchronous, automatic conflict detection, automatic membership/failover.
   - **MySQL Router**: lightweight proxy that routes the app to the current primary (single-primary mode) or distributes (multi-primary).
   - Pros: integrated, automatic, minimal data loss. Cons: latency cost of consensus, network-sensitive.
3. **Galera Cluster (Percona XtraDB Cluster / MariaDB Galera)**
   - Synchronous multi-master via certification-based replication. Strong consistency, any node writable. Cons: write latency = slowest node, hotspot/deadlock-on-commit (certification conflicts).
4. **Cloud-managed** — AWS RDS/Aurora Multi-AZ, GCP Cloud SQL HA. Aurora separates compute from a distributed storage layer (6 copies across 3 AZs) for fast failover.

### 4. Split-brain — the cardinal sin
If the network partitions and **two nodes both think they're primary**, both accept writes → divergent data, impossible to reconcile cleanly. Prevention:
- **Quorum** (majority voting) — a partition without a majority refuses to be primary. Group Replication/Galera use this; you need an **odd number** of voting members (3, 5).
- **Fencing/STONITH** — forcibly isolate/kill the old primary.
- Avoid even-numbered clusters (2 nodes can't form a majority on partition).

### 5. Failover concerns
- **Data loss window** depends on sync mode (async can lose the last transactions; semi-sync/quorum minimizes it).
- **Replication lag at failover** — promoting a lagging replica loses everything it hadn't applied.
- **Application reconnection** — connection pools must detect the topology change and reconnect (proxy/Router helps; otherwise apps need retry logic).
- **Failback** — re-introducing the recovered old primary as a replica without conflicts (GTID makes this manageable).

### 6. Proxies & connection routing
- **MySQL Router** (InnoDB Cluster), **ProxySQL** (rich: read/write split, query routing/rewriting, connection multiplexing), **HAProxy** (L4). They decouple the app's connection string from the actual primary, enabling transparent failover and read scaling.

---

## PRACTICE
> Real clusters need multiple nodes; focus on understanding + the commands you'd run.

```sql
-- Group Replication status (on a member)
SELECT * FROM performance_schema.replication_group_members;
SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;

-- Who is the current primary in single-primary mode?
SELECT MEMBER_HOST FROM performance_schema.replication_group_members
WHERE MEMBER_ROLE='PRIMARY';

-- InnoDB Cluster via MySQL Shell (mysqlsh, JS mode) — conceptual:
-- dba.createCluster('prodCluster')
-- cluster.addInstance('node2:3306')
-- cluster.addInstance('node3:3306')
-- cluster.status()             // shows topology, mode, member states

-- Semi-sync (plugin) status
SHOW STATUS LIKE 'Rpl_semi_sync_master_status';
SHOW STATUS LIKE 'Rpl_semi_sync_master_clients';
```

```text
# ProxySQL read/write split (conceptual config)
# Writers go to hostgroup 10 (primary), readers to hostgroup 20 (replicas)
# Query rules route SELECT (except FOR UPDATE) → hostgroup 20, everything else → 10
```

**Exercises (conceptual):**
1. Explain why a 2-node cluster is a bad HA design and why 3 is the minimum for quorum.
2. Describe what happens to in-flight transactions when the primary dies under (a) async, (b) semi-sync, (c) Group Replication.
3. Design the failover path for a web app: detection → promotion → traffic redirect → app reconnect. Where can data be lost?
4. Compare Group Replication vs Galera for a write-heavy, latency-sensitive app.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. What is split-brain and how do quorum-based systems prevent it?**
Split-brain is when a network partition leaves **two nodes each believing they're the primary**, both accepting writes → irreconcilable divergence. **Quorum** prevents it: a node may only act as primary if it can communicate with a **majority** of members. The minority partition voluntarily goes read-only/refuses writes. This requires an **odd** member count so a majority always exists on exactly one side.

**Q2. Why is an odd number of nodes recommended for clustering?**
To always allow a strict majority during a partition. With 2 nodes, a partition splits them 1–1 → neither has a majority → no one can safely be primary (or both wrongly assume they can). With 3, a partition yields 2 vs 1; the side of 2 keeps quorum and stays writable, the lone node steps down. 3, 5, 7 tolerate 1, 2, 3 failures respectively.

**Q3. In async replication failover, where exactly is data lost?**
The primary acknowledges commits to clients **before** replicas confirm receipt. If it dies with transactions still only in its (now-inaccessible) binlog, those committed transactions never reached the promoted replica → **lost**. Semi-sync narrows this (wait for one replica's ack); quorum/Group Replication minimizes it further by requiring majority acknowledgment.

**Q4. Group Replication vs traditional async replication + Orchestrator — trade-offs?**
**Group Replication** gives integrated, automatic failover with consensus and minimal data loss, but adds commit latency (consensus round-trips) and is sensitive to network jitter; writes must be certified (multi-primary can conflict). **Async + Orchestrator** is simpler and lower-latency but failover is bolted-on, detection/promotion is heuristic, and async means a data-loss window. Choose GR/InnoDB Cluster for strong automatic HA; async+tooling for flexibility/lower write latency.

**Q5. After failover, the application keeps trying to write to the dead primary. What's missing?**
A **routing layer** that tracks topology and a client that reconnects on it. Use **MySQL Router/ProxySQL/HAProxy** (or a VIP/DNS update + STONITH on the old node) so the app's connection string stays constant while traffic is redirected to the new primary. The app's connection pool must also detect broken connections and **retry**. Without this, the app is pinned to a dead/old node (and risks writing to a zombie primary → split-brain).

**Q6. Galera is "synchronous multi-master" — so why can a write still fail at COMMIT time?**
Galera uses **certification-based replication**: a transaction is optimistically executed locally and, at commit, certified against other nodes' write-sets. If two nodes modified the **same rows** concurrently, certification **fails for one** and that transaction is **aborted at commit** (a deadlock-like error) — the app must retry. So multi-master doesn't eliminate conflicts; it defers them to commit. Hotspot rows make this worse.

**Q7. What's the difference between HA and disaster recovery (DR)?**
**HA** handles *local/component* failures (a node, a disk) with fast automatic failover, usually within a region, near-zero downtime. **DR** handles *catastrophic* events (whole region/datacenter loss) via geographically separate copies (cross-region replicas, offsite backups), typically with larger RPO/RTO and often manual or orchestrated failover. You need both: HA for the common case, DR for the rare catastrophe.

**Q8. How does Aurora achieve fast failover compared to classic MySQL replication?**
Aurora decouples compute from a **shared distributed storage layer** (data is written as 6 copies across 3 AZs with quorum writes). Replicas read from the **same storage**, so they don't replay a binlog stream and have minimal lag; on failover, a replica is promoted in seconds because it already shares the durable storage — no data copy or long catch-up needed.

➡ Next: [Day 22 — Security & SQL Injection](day-22-security-sql-injection.md)
