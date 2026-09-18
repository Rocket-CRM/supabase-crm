# Mission

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** mission, quest, challenge, milestone, standard mission, condition, progress, waterfall, level, claim, join, accept, mission progress, condition progress, button action, claim_end_date, preview_advance_days, carry_over_progress, eligible_persona, signup_window, exclusivity, progress_reset_frequency, fn_mission_access_state, fn_distribute_mission_completion, fn_batch_reset_due_missions

**Source:** `Mission.md`

**FE-Relevant Sections:**

| Section Heading | What it contains |
|---|---|
| Concept | Standard vs milestone; activation, claim, reset, exclusivity |
| Rules | AND vs waterfall; purchase_item scoping; button_action + access gates |
| Journeys › Admin | `mission-list`, `mission-settings`, Front line claim |
| Journeys › Member | Missions hub, detail drawer, join/claim RPCs |
| System › Flows | Chokepoint → Inngest mission routers (not Kafka) |
| System › Known gaps | Form/referral conditions without chokepoint routers |

**Key RPCs (member/admin):** `bff_get_user_missions`, `bff_get_mission_detail`, `accept_mission`, `bff_claim_mission`, `bff_upsert_mission`, `bff_get_mission_details_conditions_limits`, `bff_frontline_claim_mission`, `bff_report_missions`, `bff_report_missions_rows`.

**Key business rules (summary):** Standard = all conditions must complete; milestone = waterfall levels; manual activation → join; manual claim → `unclaimed_completions`; live evaluation via `mission/evaluate` after purchase/wallet chokepoint events.

---
