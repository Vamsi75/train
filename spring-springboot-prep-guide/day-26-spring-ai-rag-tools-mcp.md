# Day 26 — Spring AI Advanced: RAG, Embeddings, Tools, Advisors & MCP

## THEORY

### 1. The problem: LLMs don't know *your* data and they hallucinate
A base model only knows its training data (a cutoff), nothing about **your** documents/database, and will confidently make things up. Two solutions: **RAG** (give it relevant context at query time) and **tool calling** (let it fetch/act via your code). These are the two pillars of production AI apps.

### 2. Embeddings & vector stores
- An **embedding** is a vector (array of floats) representing the *meaning* of text; similar meanings → nearby vectors (cosine similarity).
- An **`EmbeddingModel`** converts text → vectors. A **`VectorStore`** (PgVector, Redis, Chroma, Pinecone, Milvus, Qdrant, etc.) stores them and does **similarity search** ("find the k most semantically similar chunks to this query").
```java
@Autowired EmbeddingModel embeddingModel;
@Autowired VectorStore vectorStore;
vectorStore.add(List.of(new Document("Cert revocation requires the SCOPE_cert:revoke scope...")));
List<Document> hits = vectorStore.similaritySearch(
    SearchRequest.query("how do I revoke a certificate?").withTopK(4));
```

### 3. RAG (Retrieval-Augmented Generation) — the dominant pattern
Flow:
1. **Ingest (offline ETL):** load docs → split into chunks → embed → store in the vector store.
2. **Retrieve (query time):** embed the user's question → similarity-search the store → get top-k relevant chunks.
3. **Augment:** stuff those chunks into the prompt as context.
4. **Generate:** the LLM answers **grounded in the retrieved context** (less hallucination, cites *your* data).
Spring AI gives you both the **ETL pipeline** (`DocumentReader` → `TextSplitter`/`TokenTextSplitter` → `VectorStore` writer) and **advisors** to wire retrieval into the chat call automatically.

```java
// Query-time RAG via an advisor — retrieval happens transparently before generation
String answer = chatClient.prompt()
    .advisors(new QuestionAnswerAdvisor(vectorStore))   // retrieves top-k, injects as context
    .user("How do I revoke a certificate in Cent?")
    .call().content();
// (RetrievalAugmentationAdvisor is the newer, more configurable RAG advisor.)
```

### 4. Advisors — AOP for prompts
**Advisors** intercept the request/response around a `ChatClient` call to add cross-cutting behavior, composing in a chain:
- **`QuestionAnswerAdvisor` / `RetrievalAugmentationAdvisor`** — RAG (inject retrieved context).
- **`MessageChatMemoryAdvisor` / `PromptChatMemoryAdvisor`** — **conversation memory** (carry chat history per conversation id).
- **`SafeGuardAdvisor`** — block disallowed content.
- **Logging/observability advisors.**
```java
ChatClient chat = builder
    .defaultAdvisors(
        MessageChatMemoryAdvisor.builder(chatMemory).build(),  // remembers the conversation
        new QuestionAnswerAdvisor(vectorStore))                 // grounds answers in your docs
    .build();
// per-call conversation id:
chat.prompt().user(msg)
    .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
    .call().content();
```

### 5. Tool / Function calling — let the model *do* things
The model can decide to call **your Java methods** (to fetch live data or take actions), then incorporate the result. You expose tools with `@Tool`; Spring AI describes them to the model, executes the chosen call, and feeds the result back.
```java
@Component
class CertTools {
    private final CertService certService;
    CertTools(CertService s) { this.certService = s; }

    @Tool(description = "Look up the current status of a certificate by serial number")
    public CertStatus certificateStatus(String serial) {
        return certService.status(serial);     // real, live data from your system
    }

    @Tool(description = "Revoke a certificate. Requires confirmation.")
    public String revoke(String serial, String reason) {
        certService.revoke(serial, reason);
        return "Revoked " + serial;
    }
}

String reply = chatClient.prompt()
    .user("Is certificate ABC123 still valid, and revoke it if it's expired")
    .tools(new CertTools(certService))      // model may call certificateStatus(), then revoke()
    .call().content();
```
This bridges the LLM to your APIs/DB — turning a chatbot into an **agent** that can query and act. **Guardrail:** be very careful exposing **state-changing** tools (revoke, delete) — require confirmation, authorization, and audit; the model should not unilaterally perform destructive actions.

### 6. Model Context Protocol (MCP) — the new interoperability standard
**MCP** is an open protocol (originating from Anthropic, now broadly adopted) that standardizes how AI apps connect to **external tools, data sources, and services** via **MCP servers**. Spring AI 1.0 has **first-class MCP support** (client + server starters): your Spring app can be an **MCP client** (consuming tools exposed by MCP servers) or an **MCP server** (exposing your services as tools to any MCP-compatible AI host, e.g., Claude Desktop, IDE agents). It's "USB-C for AI tools" — write the integration once, use it from any MCP-aware client.
```xml
<dependency>
  <groupId>org.springframework.ai</groupId>
  <artifactId>spring-ai-starter-mcp-server</artifactId>   <!-- or -mcp-client -->
</dependency>
```

### 7. ETL ingestion pipeline (where RAG quality is won or lost)
- **DocumentReader** — read PDFs, HTML, Markdown, JSON (Tika reader handles many formats).
- **TextSplitter / TokenTextSplitter** — **chunking** strategy massively affects retrieval quality (too big → noisy/over-budget context; too small → lost meaning). Tune chunk size + overlap.
- **Metadata** — attach source/section so you can **cite** and **filter** (e.g., only this org's docs).
- **VectorStore writer** — embed + persist.

### 8. Prompt injection & RAG security
Retrieved/user content can contain **prompt-injection** attacks ("ignore previous instructions..."). Mitigations: keep **system instructions authoritative**, **don't blindly trust retrieved text as instructions**, restrict tools (especially destructive ones) behind **authorization**, validate/sanitize, and **filter the vector store by tenant** so one org can't retrieve another's data (multi-tenant isolation).

---

## PRACTICE

```java
// 1) Ingest docs into a vector store (offline)
@Service
class IngestionService {
    private final VectorStore vectorStore;
    IngestionService(VectorStore vs) { this.vectorStore = vs; }

    public void ingest(Resource doc) {
        List<Document> docs = new TikaDocumentReader(doc).read();
        List<Document> chunks = new TokenTextSplitter().apply(docs);   // chunking
        vectorStore.add(chunks);                                       // embed + store
    }
}

// 2) RAG + memory + tools, composed via advisors
@Service
class CentCopilot {
    private final ChatClient chat;
    CentCopilot(ChatClient.Builder b, VectorStore vs, ChatMemory memory, CertTools tools) {
        this.chat = b
            .defaultSystem("You are Cent Copilot. Answer ONLY from provided context; " +
                           "if unknown, say so. Never reveal another org's data.")
            .defaultAdvisors(
                MessageChatMemoryAdvisor.builder(memory).build(),
                new QuestionAnswerAdvisor(vs))
            .defaultTools(tools)
            .build();
    }
    public String ask(String sessionId, String orgId, String question) {
        return chat.prompt()
            .user(question)
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            // filter retrieval to the caller's org (multi-tenant isolation)
            .call().content();
    }
}
```

**Exercises:**
1. Build a tiny RAG app: ingest a Markdown doc, then answer a question using `QuestionAnswerAdvisor`; confirm the answer is grounded (ask something only in the doc).
2. Add `MessageChatMemoryAdvisor` and prove multi-turn memory (reference an earlier answer).
3. Expose a read-only `@Tool` and watch the model call it for live data; then discuss what guardrails a *write* tool needs.
4. Turn your service into an **MCP server** (add the starter) and connect an MCP client to it.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. What is RAG and what problem does it solve?**
**Retrieval-Augmented Generation**: at query time you **retrieve relevant chunks** of *your* data (via embedding similarity search in a vector store) and **inject them into the prompt** as context, so the LLM answers **grounded in your data** instead of only its training knowledge. It solves two big problems: the model **doesn't know your private/up-to-date data**, and it **hallucinates**. RAG provides authoritative context (and lets you cite sources), dramatically improving accuracy without retraining the model.

**Q2. Embeddings and vector stores — how does similarity search work?**
An **embedding** maps text to a high-dimensional **vector** capturing semantic meaning; semantically similar texts produce vectors that are **close** (e.g., by cosine similarity). A **vector store** indexes these vectors and, given a query vector, returns the **top-k nearest** documents — i.e., the most *meaning-similar* chunks, not keyword matches. That's why RAG can find relevant content even when the user's wording differs from the document's. Spring AI abstracts the store (PgVector, Redis, Chroma, etc.) behind `VectorStore`.

**Q3. What are Advisors in Spring AI?**
Advisors are **interceptors around `ChatClient` calls** — effectively **AOP for prompts**. They form a chain that can modify the request before it hits the model and the response after. Built-in ones implement **RAG** (`QuestionAnswerAdvisor`/`RetrievalAugmentationAdvisor` inject retrieved context), **conversation memory** (`MessageChatMemoryAdvisor` adds chat history by conversation id), and safety/logging. They let you compose cross-cutting AI behaviors declaratively instead of hand-coding retrieval/memory into every call.

**Q4. Tool/function calling — how does it work and what's the danger?**
You expose Java methods as **tools** (`@Tool` with a description). Spring AI sends the tool **schemas** to the model; if the model decides a tool is needed, it returns a **tool-call request**, Spring AI **executes your method**, feeds the result back, and the model continues — so the LLM can fetch live data or **take actions** (becoming an agent). **Danger:** exposing **state-changing/destructive tools** (revoke, delete, transfer) means the model could trigger them from manipulated input. Guardrails: require explicit confirmation, enforce **authorization** on the tool itself, audit every call, and prefer read-only tools — never let the model unilaterally perform irreversible actions.

**Q5. What is MCP and why does it matter?**
**Model Context Protocol** is an open standard (from Anthropic, widely adopted) for connecting AI applications to **external tools/data via MCP servers** — "USB-C for AI integrations." Instead of bespoke per-app integrations, you implement an MCP **server** once and any MCP-aware **client** (Claude Desktop, IDE agents, other apps) can use it; or your app acts as a **client** consuming others' tools. **Spring AI 1.0 has first-class MCP client + server starters**, so you can expose your Spring services as standardized AI tools (or consume them) with minimal code. It matters because it standardizes the fragmented tool-integration space.

**Q6. Why does chunking strategy make or break a RAG system?**
Retrieval quality depends on the **chunks** you embedded. **Too large** → each chunk is noisy and dilutes the relevant bit, wastes context-window/tokens, and lowers similarity precision. **Too small** → chunks lose surrounding meaning, so retrieval returns fragments that don't fully answer the question. Good chunking (sensible size + **overlap**, respecting semantic boundaries like headings/paragraphs) plus **metadata** for filtering/citation is where RAG accuracy is actually won — the model can only be as good as the context you retrieve and feed it.

**Q7. How do you prevent prompt injection and cross-tenant data leakage in a RAG/agent app?**
**Prompt injection:** treat retrieved documents and user input as **untrusted data, not instructions** — keep the **system prompt authoritative**, don't let retrieved text override rules, sanitize/validate, and gate **tools (especially destructive ones) behind real authorization** rather than trusting the model's judgment. **Cross-tenant leakage:** **filter the vector store by tenant/org** (metadata filters) so a query can only retrieve the caller's documents, scope tools to the authenticated user's permissions, and never embed multiple tenants' data into a shared, unfiltered index. Security boundaries must live in *your* code, not in the prompt.

**Q8. RAG vs fine-tuning — when would you choose each?**
**RAG** injects external knowledge at query time — best for **frequently-changing, factual, or private data**, gives **citations**, is cheap to update (just re-index), and avoids retraining. **Fine-tuning** adjusts the model's weights — best for teaching **style/format/behavior** or domain language the model should *internalize*, when you have quality labeled data and the knowledge is **stable**. They're complementary: RAG for "what does it know," fine-tuning for "how does it behave." Most production apps start with RAG (lower cost/risk) and fine-tune only when prompting+RAG can't achieve the needed behavior.

➡ Next: [Day 27 — Production Readiness & Incident Playbook](day-27-production-readiness-issues.md)
