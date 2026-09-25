# Rocket Demo — CS seed (AOPs + knowledge + inbox)

Merchant **Rocket Demo** (`rocket-demo` / `fae172a5-de90-440e-a766-db6a5982cc9b`).

Story: **Rocket Clinic** (aesthetic packages) + **Rocket Club** retail skincare under one tenant.

## What was seeded (live DB)

| Surface | Count (approx) | Notes |
|--------|----------------|--------|
| AOPs (`cs_procedures`) | 5 active | intents below |
| Knowledge (`cs_knowledge_articles`) | ~23 active | `source_type=demo_seed`, `source_url=seed://rocket-demo/cs` |
| Inbox resources | 13 QR + 7 rich + 3 links | codes `RKT-*` |
| Categories | 4 | Greeting, Orders, Clinic, Product |

### AOPs

| Intent | Name | Flexibility |
|--------|------|-------------|
| `product_inquiry` | Knowledge Reply Handler | guided |
| `appointment_booking` | Clinic Package Booking | guided (+ agentic propose) |
| `order_tracking` | Order Tracking Handler | guided |
| `place_order` | Ecommerce Order Assistant | guided (+ agentic search) |
| `medical_advice` | Medical Specialist Route | strict |

Booking “API” in v1 = `@Create Ticket` with type `clinic_booking` (durable write until clinic booking stubs exist). Tracking/ecommerce use registry tools (`lookup_order`, `get_order_shipping`, `search_products`, `check_promotion`, `create_order`).

### Re-run locally authored SQL

Files in this folder are the source of truth for re-seed:

```bash
# Apply via Supabase MCP execute_sql / apply_migration (no local Postgres required)
# 01_inbox_resources.sql
# 02_knowledge_articles.sql
# 03_procedures.sql
```

Idempotency keys:

- Resources: delete `resource_code LIKE 'RKT-%'` then insert
- Knowledge: delete `source_type='demo_seed' AND source_url='seed://rocket-demo/cs'`
- Procedures: delete by the five `trigger_intent` values above

### Smoke checks (admin)

1. Inbox Content Panel → search “Welcome” / “Clinic Package Menu”
2. Knowledge admin → filter category `clinic_packages` / `medical_boundary`
3. Procedures admin → five active intents listed above

### Demo chat prompts

1. “มีแพ็กเกจเลเซอร์อะไรบ้าง อยากจองวันพุธบ่าย”
2. “GlowLab niacinamide ใช้ยังไง / มีโปรอะไร”
3. “เช็คพัสดุออเดอร์ RKT-ORD-100234 ช้อปปี้”
4. “อยากสั่ง AgeSoft Retinol ส่งที่บ้าน”
5. “หนูเป็นฝ้าไหม ควรกินยาอะไร” → must refuse + offer clinic/specialist
