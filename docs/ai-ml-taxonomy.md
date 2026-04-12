# AI / ML Taxonomy — A Multi-Dimensional Framework

Understanding AI/ML requires thinking in **multiple independent dimensions**, not a single hierarchy. Every AI system is a coordinate across all of these axes.

---

## The Four Axes

### Axis 1 — Learning Paradigm (How does it get feedback?)

| Paradigm | Signal | Example |
|---|---|---|
| **Supervised** | Human-provided labels (input → correct output) | Spam detection, medical diagnosis |
| **Unsupervised** | No labels; find structure on its own | Customer segmentation, anomaly detection |
| **Self-supervised** | Labels generated from the data itself | GPT pre-training (predict next word), masked image modeling |
| **Reinforcement** | Reward/penalty signal from environment | Game AI, robotics, RLHF |

### Axis 2 — Model Architecture (What computes the answer?)

| Architecture | Characteristics | Example |
|---|---|---|
| **Linear models** | Simple, interpretable | Logistic regression |
| **Tree-based** | Decision rules, good on tabular data | Random Forest, XGBoost |
| **SVMs** | Optimal boundary in high-dimensional space | Text classification (older era) |
| **Shallow neural nets** | 1–2 hidden layers | Simple perceptron |
| **Deep neural nets** | Many layers ("deep learning") | CNN, RNN, Transformer |

### Axis 3 — Task Type (What is it trying to do?)

| Task | Output | Example |
|---|---|---|
| **Classification** | Category label | Is this email spam? |
| **Regression** | Continuous number | Predict customer lifetime value |
| **Clustering** | Group assignment | Segment customers into personas |
| **Generation** | New content | Write text, create images |
| **Ranking** | Ordered list | Search results, recommendations |
| **Decision-making** | Action to take | Which offer to show a customer |
| **Planning** | Sequence of actions toward a goal | Robot navigation, game strategy |

### Axis 4 — Data Modality (What type of input?)

| Modality | Common architectures |
|---|---|
| **Tabular** | Trees, linear models, shallow nets |
| **Text** | Transformers (LLMs) |
| **Image** | CNNs, Vision Transformers |
| **Audio** | CNNs, Transformers (Whisper) |
| **Video** | 3D CNNs, Video Transformers |
| **Multimodal** | GPT-4o, Gemini (text + image + audio) |

---

## Every system = a coordinate

```
System = (Paradigm, Architecture, Task, Modality)
```

| System | Paradigm | Architecture | Task | Modality |
|---|---|---|---|---|
| XGBoost churn model | Supervised | Tree-based | Classification | Tabular |
| K-means segmentation | Unsupervised | Linear (centroid) | Clustering | Tabular |
| GPT pre-training | Self-supervised | Deep (Transformer) | Generation | Text |
| ChatGPT / Claude (RLHF stage) | Reinforcement | Deep (Transformer) | Generation | Text |
| AlphaGo | Reinforcement | Deep (CNN + search) | Decision-making | Image (board) |
| Stable Diffusion | Self-supervised | Deep (Diffusion / UNet) | Generation | Image |
| Whisper | Supervised | Deep (Transformer) | Classification | Audio |
| GPT-4o | Self-sup + RL | Deep (Transformer) | Generation | Multimodal |
| Hightouch AI Decisioning | Reinforcement | Traditional ML (bandits) | Decision-making | Tabular |

---

## Common misconceptions

### "Deep Learning" vs "Unsupervised Learning"

These are **not** on the same axis. Deep learning is a model architecture (Axis 2). Unsupervised is a learning paradigm (Axis 1). A system can be both — an autoencoder is deep learning AND unsupervised.

### "Reinforcement Learning" vs "Deep Learning"

Also different axes. RL is a paradigm (Axis 1); deep learning is an architecture (Axis 2). "Deep Reinforcement Learning" (e.g., AlphaGo) combines both — RL paradigm with deep neural net architecture.

### "LLM" is not an axis value

LLM is a **composite** — it sits at a specific intersection:
- Axis 1: Self-supervised (pre-training) + RL (RLHF fine-tuning)
- Axis 2: Deep Learning (Transformer)
- Axis 3: Generation
- Axis 4: Text

---

## Hightouch AI Decisioning — A Case Study

Hightouch uses **reinforcement learning (contextual bandits)** at its core, not LLMs. Here's why this maps correctly:

| Axis | Choice | Reasoning |
|---|---|---|
| Paradigm | **RL** (contextual bandits) | Continuous explore/exploit loop with real outcome feedback |
| Architecture | **Traditional ML** (lightweight bandits) | Fast, cheap, millions of decisions/day |
| Task | **Decision-making** | "Which message, channel, timing for this customer?" |
| Modality | **Tabular** | Customer features: purchase history, engagement, demographics |

### Why RL over LLM for decisioning?

| Factor | RL (Bandits) | LLM |
|---|---|---|
| Core job | Pick optimal action from a fixed set | Generate new content |
| Learns from outcomes | Yes, continuously | No — frozen after training |
| Action space | Constrained (marketer-defined) | Open-ended |
| Cost per decision | Very cheap (milliseconds) | Expensive (API call + tokens) |
| Hallucination risk | Zero (picks from approved options) | Present |
| Best for | "Which of these 50 emails should customer X get?" | "Write me a new email for this persona" |

Hightouch uses LLMs **at the edges** — for semantic tagging of content, understanding templates, and generating new content variants. The RL core decides; the LLM assists.

---

## The Future of LLMs — and LeCun's Alternative

### How LLMs work today

LLMs learn by predicting the next token (word) given all previous tokens. This is repeated billions of times across trillions of words from the internet, books, code, and conversations.

**To correctly predict the next word, the model is forced to learn an enormous amount as a side effect:**

- "Water boils at ___" → must learn physics facts
- "The CEO of Apple is ___" → must learn world knowledge
- "She felt sad because ___" → must learn causality and emotion
- `if (x > 0) return ___` → must learn programming logic

The result is an incredibly capable autocomplete system. But there's a fundamental question: **is this enough?**

### LeCun's critique

Yann LeCun (Chief AI Scientist at Meta, Turing Award winner) argues **no**. His position:

> LLMs are "word models," not "world models." They learn statistical patterns of language — which word tends to follow which — but they never develop genuine understanding of how the world works.

**The glass example:**

An LLM sees text:
```
"The glass was pushed off the table. It ___"
→ Predicts: "shattered"
```
It gets the right answer because it has seen similar sentences millions of times. But it has **no concept** of glass, gravity, edges, or impact. It doesn't know why the glass shattered — only that "shattered" is the statistically likely next word after that sequence.

A toddler who has never read a single sentence already understands that pushing a glass off a table will make it fall and break. They learned this from **one or two experiences** — not from reading about it.

### LeCun's alternative: JEPA and World Models

LeCun proposes a fundamentally different architecture called **JEPA** (Joint Embedding Predictive Architecture). The core idea:

**Instead of predicting the next word from text, predict what happens next from observing the world — at an abstract level.**

| | LLM | JEPA / World Model |
|---|---|---|
| **Learns from** | Text on the internet | Observing the world (video, interaction) |
| **Predicts** | The next word | What happens next (abstractly) |
| **Can plan?** | No — generates one token at a time | Yes — simulates futures, picks best path |
| **Understands physics?** | No — knows what people *write about* physics | Yes — learned from *watching* the physical world |
| **Analogy** | Someone who read every book but never left a room | A child exploring and learning by doing |

#### Why "abstract" is the key insight

Consider watching a video of someone pouring coffee:

**Pixel-level prediction** (what generative AI models do): Predict the exact color, position, and shape of every liquid particle in the next frame. Impossibly hard and wastes capacity on irrelevant details like the exact steam pattern.

**Abstract prediction** (what JEPA does): "The cup will be more full. The pot will be lighter. The liquid level will rise." It ignores irrelevant details and captures **what actually matters** — just like human mental models.

#### The full cognitive architecture

LeCun envisions a modular system with distinct components working together:

```
┌───────────────┐
│  Perception    │  ← Observes the world (vision, sensors)
└───────┬───────┘
        ▼
┌───────────────┐
│  World Model   │  ← The JEPA core: "if I do X, then Y happens"
└───────┬───────┘
        ▼
┌───────────────┐
│  Objectives    │  ← Goals and constraints
└───────┬───────┘
        ▼
┌───────────────┐
│   Planner      │  ← Simulates possible action sequences, picks best
└───────┬───────┘
        ▼
┌───────────────┐
│    Actor       │  ← Executes the chosen action
└───────┬───────┘
        ▼
┌───────────────┐
│   Memory       │  ← Stores past experiences for future use
└───────────────┘
```

This looks far more like how humans think than "predict the next token":

1. **I see** the world (perception)
2. **I have a mental model** of how things work (world model)
3. **I have a goal** I want to achieve (objective)
4. **I imagine** different actions and predict outcomes for each (planning)
5. **I pick** the action whose predicted outcome best matches my goal (decision)
6. **I do it** and **remember** what happened (action + memory)
7. **I update** my mental model (learning)

Compare to how an LLM works:

1. I see some text
2. I predict the next word
3. That's it

#### Current implementations

Meta has built early JEPA systems:
- **I-JEPA** — learns visual representations from images
- **V-JEPA 2** — 1.2 billion parameters, learns from video, demonstrates prediction and planning capabilities

These are still early research — nothing close to replacing LLMs for practical use yet.

### The three camps

| Camp | Belief | Key proponents |
|---|---|---|
| **World Models** | LLMs will hit a ceiling. You need grounded world models that learn from experience, not text. | Yann LeCun (Meta) |
| **Scaling** | Scale LLMs + RLHF + chain-of-thought further and intelligence keeps emerging. Text may be enough. | Sam Altman (OpenAI), Dario Amodei (Anthropic) |
| **Hybrid** | Both are needed. LLMs for language, world models for physical reasoning, RL for decision-making. | Most pragmatic practitioners |

The Hightouch architecture (RL core + LLM at the edges) is already a practical example of the hybrid approach — using the right model type for each dimension of the problem.

---

## Quick Reference: The Grid

Every real system sits at an intersection. Here is the full grid by paradigm and architecture:

```
                    Traditional ML          Deep Learning
                    ──────────────          ─────────────
Supervised          Decision Tree, SVM      CNN, BERT, Whisper
Unsupervised        K-means, PCA            Autoencoder, VAE, GAN
Self-supervised     (rare)                  GPT pre-training, JEPA
Reinforcement       Q-table                 DQN, PPO, AlphaGo
```

And by paradigm and task:

```
                    Classification   Generation   Decision-making   Planning
                    ──────────────   ──────────   ───────────────   ────────
Supervised          Spam filter      (rare)       (rare)            (rare)
Unsupervised        Anomaly detect   GANs         —                 —
Self-supervised     BERT             GPT, DALL-E  —                 JEPA (emerging)
Reinforcement       —                RLHF stage   Bandits, AlphaGo  AlphaZero, MuZero
```
