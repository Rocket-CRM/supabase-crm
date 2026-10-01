# Tag & Persona

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** tag, persona, segment, persona group, user type, buyer, seller, VIP, classification, behavioral marker, assign persona, assign tag, user tags

**Source:** `Tag_and_Persona.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Concept — persona vs tag matrix | 7–30 | When to use persona vs tag |
| Rules | 32–45 | Assignment, user_type, idempotency, tier gates |
| Journeys — Admin | 49–75 | Tier Personas, User Tags, Customer 360, AMP |
| Journeys — Member | 77–96 | Signup, profile, eligibility errors |
| System — Data model | 100–126 | Tables, ER diagram |
| System — Functions | 128–147 | `assign_persona`, `assign_tag`, BFFs |
| System — Flows | 149–159 | Assign paths |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Doc section |
|---|---|---|---|
| `assign_persona(p_user_id, p_persona_id)` | `p_user_id (uuid)`, `p_persona_id (uuid, nullable)` | JSONB: success, persona/group names, user_type change | Rules, System › Functions |
| `assign_tag(...)` | `p_user_id`, `p_tag_id`, `p_action` (`add`/`remove`), optional `p_source_type`, `p_source_id` | JSONB: success, tag name, action | Rules, System › Functions |
| `bff_admin_change_member_persona` | admin wrapper | same as assign | Journeys › Admin |
| `bff_admin_assign_member_tag` | admin wrapper | tag chips on C360 | Journeys › Admin |

**Key Business Rules (summary):**
- Users have exactly one persona (or none) — represents business profile
- Users can have unlimited tags — represents behavioral attributes
- Assigning a persona from a group with `user_type` automatically updates the user's `user_type`
- Removing persona does NOT revert user_type
- Tags are idempotent: adding an already-assigned tag returns success silently
- All operations enforce merchant isolation

---
