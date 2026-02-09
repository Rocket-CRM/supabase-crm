# Agentic Loyalty Architecture: The "Post-AI" Decision Engine

## Overview
This document outlines the architecture for a next-generation "Post-AI" Loyalty & Marketing Platform. Unlike traditional CDPs (which just move data) or traditional Marketing Automation (which relies on static rules), this system uses **Real-Time Stream Processing** combined with **Agentic AI Reasoning** to make decisions.

**Core Philosophy:** "Don't just predict scores. Understand context, reason about intent, and generate actions."

---

## The Architecture Diagram

```mermaid
graph TD
    subgraph "Ingestion Layer (The Funnel)"
        A[Website/App Events] -->|Webhook| D{Kafka / Redpanda}
        B[ML Scores (Snowflake)] -->|Stream| D
        C[Service/Support] -->|Webhook| D
    end

    subgraph "The State Engine (RisingWave)"
        D -->|Stream Ingest| E[Raw Events Table]
        E -->|Continuous Aggregation| F[View: Real-Time Stats]
        E -->|Window Function| G[View: Event Chronology]
        F & G -->|Join| H[Materialized View: Unified Context]
        
        Z[Asset Sources] -->|Sync| Y[Asset Table (Static)]
        H -.->|Context| MCA
        Y -.->|Vector Search| MCA
    end

    subgraph "MCA (Marketing Control Agent)"
        I[Trigger Service] -->|Detect Opportunity| J[Orchestrator API]
        J -->|1. Query Context (ms)| H
        
        subgraph "The Reasoning Loop"
            J -->|2. Context + Goal| K((Llama 3 AI))
            K -->|3. Tool Call: Search| M[MCP: Asset Search]
            M -->|Vector Search| Y
            M -->|Results| K
            K -->|4. Tool Call: Act| N[MCP: Action Layer]
        end
    end

    subgraph "Action Layer (MCP Tools)"
        N -->|Tool: Send Coupon| O[Loyalty API]
        N -->|Tool: Send SMS| P[Twilio/Braze]
        N -->|Tool: Update CRM| Q[Salesforce]
    end

    style H fill:#f96,stroke:#333,stroke-width:2px,color:black
    style K fill:#9cf,stroke:#333,stroke-width:2px,color:black
```

---

## 1. The Ingestion Layer ("The Funnel")
*   **Goal:** Normalize all enterprise data into a single event stream.
*   **Components:**
    *   **Sources:**
        *   **Loyalty/Commerce:** "User bought X", "User earned Y points".
        *   **ML Models:** "User Churn Risk updated to 0.9" (Streamed from Warehouse).
        *   **Service:** "User opened ticket #123".
    *   **Transport:** **Kafka / Redpanda**. Acts as the shock absorber.
    *   **Gateway:** A lightweight Edge Function (`POST /ingest`) that authenticates and pushes to Kafka.

## 2. The State Engine ("RisingWave")
*   **Goal:** Maintain the "Living State" of every user in real-time memory.
*   **Technology:** **RisingWave** (Streaming Database).
*   **Key Views:**
    1.  **Event Chronology:** A sliding window (e.g., last 20 events) preserving the *sequence* of actions. (Critical for AI to understand cause-and-effect).
    2.  **Real-Time Stats:** Aggregates (LTV, Point Balance) calculated instantly on write.
    3.  **Unified Context:** A single JSON object merging Stats + Chronology.
    4.  **Asset Table:** A static table containing Rewards/Coupons with **Vector Embeddings** for semantic search.

## 3. The MCA (Marketing Control Agent)
*   **Goal:** The "Brain" that decides *what* to do.
*   **Components:**
    *   **Trigger:** Listens to the stream for "Actionable Events" (e.g., Session Start, Cart Abandon, Tier Upgrade). Wakes up the API.
    *   **Orchestrator:** The API/Edge Function that manages the conversation.
    *   **The AI:** **Llama 3 (via Groq/Ollama)**. Fine-tuned or System Prompted for loyalty logic.

### The "Agentic Search" Flow
Instead of a dumb vector match, we use **Tool Calling**:
1.  **Analyze:** AI reads User Context ("User bought tent").
2.  **Reason:** AI determines need ("User needs stove").
3.  **Tool Call:** AI invokes `search_assets("camping stove")`.
4.  **Retrieval:** System runs Vector Search against RisingWave Asset Table.
5.  **Select:** AI picks the best asset from the results.

## 4. The Action Layer ("MCP Tools")
*   **Goal:** Execute the decision safely.
*   **Technology:** **MCP (Model Context Protocol)**.
*   **Mechanism:** Actions are exposed as tools to the AI.
    *   `send_coupon(id, reason)`
    *   `send_sms(phone, text)`
*   **Safety:** The Orchestrator verifies parameters/budget before executing the actual API call to 3rd party providers (Braze, Twilio, etc.).

---

## Competitive Advantage vs. Hightouch/CDPs

| Feature | Traditional CDP / Hightouch | Our "Post-AI" Architecture |
| :--- | :--- | :--- |
| **Data Freshness** | **Batch** (15m - 1hr latency). "Zero Copy" relies on slow Warehouse queries. | **Streaming** (ms latency). RisingWave maintains live state. |
| **Context** | **Snapshot**. "User has 500 points." | **Narrative**. "User has 500 points AND just complained about shipping." |
| **Decision Logic** | **Discriminative**. "If Score > 0.8, Send Template A." | **Generative**. "Score is 0.8, but context implies 'Fit Anxiety'. Send Size Guide." |
| **Asset Selection** | **Hard Rules**. "Category = Shoes". | **Semantic Search**. "Find rewards that match 'Camping Vibe'." |

## Implementation Roadmap (MVP)

1.  **Setup Infrastructure:**
    *   Docker Compose: Redpanda + RisingWave + MinIO (S3).
2.  **Ingestion:**
    *   Create `raw_events` topic.
    *   Build `POST /api/event` Edge Function.
3.  **State Definition:**
    *   Write RisingWave SQL for `unified_context` view.
    *   Enable Vector Index on `assets` table.
4.  **The Brain:**
    *   Build `decision-engine` Edge Function.
    *   Integrate Llama 3 (via Groq) with Tool Calling definitions.






















