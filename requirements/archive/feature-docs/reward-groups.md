# Feature Guide: Reward Groups & Max Distinct Reward

## 1. Overview

Reward Groups let merchants bundle multiple rewards together and control how members pick from that bundle — not just how many units they can take, but how many *types* they can choose. A member walking up to a "Zone Tickets" group with six seat categories shouldn't be able to claim all six; Reward Groups enforce exactly that constraint.

The core mechanic is **Max Distinct Reward**: a per-group, per-user limit on the number of distinct reward types a member may redeem. A member who has already claimed "Zone A" seats cannot add "Zone B" if Max Distinct = 1 — but they can redeem more "Zone A" units as long as Zone A's own quota allows it. Re-redeeming a type the member already owns never consumes an additional distinct slot.

This composes cleanly with two pre-existing limit types. Max Distinct answers "which types can the user pick?" Group Quantity answers "how many total units across the group?" Reward Quota answers "how many units of this specific reward?" All three are independent and stack: each check runs in sequence, and the member must pass all that are configured.

---

## 2. Key Concepts

**Reward Group** — A named container grouping one or more rewards under shared limit enforcement. A reward may belong to multiple groups simultaneously. Example: "Cinema Tickets" containing Zone A, Zone B, Zone C rewards.

**Max Distinct Reward** — A limit on the number of *distinct reward types* a user may redeem inside a group, within a given time window. Only `scope = user` is valid. Re-redeeming an already-chosen type does not consume an additional slot.

**Group Quantity Limit** — A cap on the *total units* a user (or all users) may redeem across all rewards in the group combined. Uses `metric = quantity`, `entity_type = reward_group`.

**Reward Quota Limit** — A cap on the *total units* of one specific reward a user (or all users) may redeem. Uses `metric = quantity`, `entity_type = reward`.

`**transaction_limits.metric`** — The column that differentiates Max Distinct from Quantity limits. Values: `quantity` (default) or `distinct_reward`.

**Distinct Slot** — One slot consumed when a user redeems a reward type for the first time within the time window. Subsequent redemptions of the same type do not consume another slot.

`**CONFLICTING_GROUP_LIMITS`** — A save-time error raised when `max_distinct > group_quantity` on the same group at `scope = user`. This configuration is mathematically contradictory (e.g., "pick 2 types" but "only 1 unit total") and is blocked before it reaches members.

---

## 3. Configuration Reference

### Reward Group Fields


| Field          | Type         | Required | Notes                                          |
| -------------- | ------------ | -------- | ---------------------------------------------- |
| Group Name     | Text         | Yes      | Display name shown in admin and error messages |
| Group Code     | Text         | No       | Human-readable identifier, unique per merchant |
| Description    | Text         | No       | Internal notes                                 |
| Is Featured    | Boolean      | No       | Default false. When true, group is surfaced in a carousel/featured section on the member-facing catalog |
| Member Rewards | Multi-select | Yes      | Rewards assigned to this group                 |


### Limit Fields (per limit row on the group)


| Field     | Values                               | Notes                                                            |
| --------- | ------------------------------------ | ---------------------------------------------------------------- |
| Metric    | `Reward Type` / `Reward Quantity`    | `Reward Type` = Max Distinct; `Reward Quantity` = Group Quantity |
| Count     | Integer ≥ 1                          | The limit ceiling                                                |
| Scope     | `Per User` / `Total`                 | Max Distinct only supports Per User                              |
| Time Unit | Day / Week / Month / Year / All Time | Window for counting                                              |


### Limit Combinations & What They Express


| Goal                              | Configure                                          |
| --------------------------------- | -------------------------------------------------- |
| Pick 1 type, any qty per type     | Max Distinct = 1 (no Group Qty limit)              |
| Pick 1 type, 1 unit only          | Max Distinct = 1 + Reward Quota = 1 on each reward |
| Pick 2 types, any qty each        | Max Distinct = 2 (no Group Qty limit)              |
| Pick up to M types, N total units | Max Distinct = M + Group Qty = N (N must ≥ M)      |
| Total N units, any type mix       | Group Qty = N only (no Max Distinct)               |


> **Guardrail:** Max Distinct = M + Group Qty = 1 on the same group at the same scope is rejected at save (`CONFLICTING_GROUP_LIMITS` / RWD019). You cannot pick 2 types if only 1 unit total is allowed.

---

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`


| Page                         | Route Reference                   | BFF                                                                   |
| ---------------------------- | --------------------------------- | --------------------------------------------------------------------- |
| Reward Group List            | Loyalty → Rewards → Reward Groups | `bff_list_reward_groups` — now returns `is_featured` per row         |
| Reward Group Form (New/Edit) | Reward Group List → New / Edit    | `bff_get_reward_group_details` (returns `is_featured`), `bff_upsert_reward_group_with_limits` (accepts `p_is_featured boolean DEFAULT false`) |


**Creating a Reward Group:**

1. From **Reward Group List**, click **New Group**.
2. Enter Group Name and optional Group Code.
3. In the **Members** panel, search and add rewards to the group.
4. In the **Limits** panel, click **Add Limit**:
  - Choose **Metric**: "Reward Type" for Max Distinct, "Reward Quantity" for Group Quantity.
  - Set **Count**, **Scope**, and **Time Unit**.
  - Add additional limit rows as needed (e.g., one Max Distinct row + one Group Quantity row).
5. Click **Save**. System validates no `CONFLICTING_GROUP_LIMITS` condition. If conflict detected, save is blocked with an inline error.

**Editing limits:** Open the group's edit form, modify limit rows, save again. Changes apply immediately to future redemptions.

**Deleting a group:** From the list, delete the group. All `transaction_limits` rows for the group are removed. Rewards are not deleted — they lose their group membership.

> **Common mistake:** Setting Max Distinct = 2 and Group Qty = 1. This is blocked at save. Group Qty must always be ≥ Max Distinct when both are configured for the same scope.

---

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`


| State            | Page                    | Notes                                                          |
| ---------------- | ----------------------- | -------------------------------------------------------------- |
| Browsing catalog | Reward Catalog          | `api_get_rewards_full_cached` returns `reward_group_ids[]` per reward and a top-level `groups{}` map with name, `is_featured`, and limits — no second round-trip needed |
| Checking quota   | Reward Catalog / Detail | `api_get_my_reward_group_usage()` returns live quota per group including `redeemed_reward_ids[]` |
| Chosen badge     | Reward Card             | Reward ID is in `redeemed_reward_ids` → green "Chosen ✓" — re-redeem allowed subject to individual reward quota |
| Locked badge     | Reward Card             | Reward ID is NOT in `redeemed_reward_ids` AND `remaining = 0` → red "Locked" — group's distinct limit is full |
| Redeeming        | Reward Detail → Confirm | Limit check happens server-side at redemption time via `fn_check_reward_group_limits` |
| Blocked          | Reward Detail           | Error drawer shown with remaining quota and limit description (RWD018) |
| Featured group   | Reward Catalog          | Groups with `is_featured = true` are surfaced in a carousel section above the main grid |


**Happy path (Max Distinct = 1, Group = Zone A / Zone B / Zone C):**

1. Member opens **Reward Catalog** and taps Zone A.
2. Taps **Redeem** — points deducted, Zone A redeemed. Distinct count = 1.
3. Member opens Zone B. Taps **Redeem** — server calls `fn_check_reward_group_limits`, sees distinct count = 1, limit = 1 → **blocked**.
4. Error drawer: *"You can pick up to 1 distinct reward(s) in Cinema Tickets. You have already picked 1."*
5. Member returns to Zone A and redeems again — same type, distinct count stays at 1 → **allowed** (subject to Zone A's own Reward Quota).

**Repeat redemption (same type, still allowed):**

Redeeming Zone A a second time does not increment the distinct count. The group's Max Distinct check sees `COUNT(DISTINCT reward_id)` = 1 and `is_new = false`, so no additional slot is consumed.

---

## 6. Perspectives

### 6a. For Customer Success

**Onboarding script:** "Reward Groups let you control which rewards a customer can pick together. If you have three seat zones and you only want a customer to choose one, create a group with those three rewards and set Max Distinct = 1."

**FAQ:**

- *"A customer redeemed Zone A twice — is that a bug?"* No. Repeat redemptions of the same type are allowed by Max Distinct. To prevent this, add a Reward Quota = 1 on Zone A itself.
- *"Why can't I save my group?"* If you see "Conflicting Group Limits," your Max Distinct count is higher than your Group Quantity limit. Either raise Group Qty or lower Max Distinct.
- *"Can a reward be in two groups at once?"* Yes. Each group enforces its own limits independently. The member must pass all groups' checks to redeem.

**Troubleshooting (member says they're blocked unexpectedly):** Check the group's Max Distinct and time window. The count is `COUNT(DISTINCT reward_id)` within the window — if the window is "all time" and the member redeemed this type a year ago, the slot is still consumed.

### 6b. For Marketing

Reward Groups solve the "pick one from the menu" problem. Instead of showing members a single reward, you can present an entire reward category and guarantee each member walks away with only their one chosen type — creating scarcity and perceived exclusivity without complex eligibility rules. The "Zone Tickets" example is classic: members feel they have freedom of choice, but the business maintains strict control over which categories each customer enters.

Max Distinct also supports "choose 2 from 5" mechanics — a proven engagement pattern in loyalty (gift-with-purchase, trial bundles) that's previously required custom engineering per campaign.

### 6c. For Testers

**Key assertions for `fn_check_reward_group_limits`:**


| Scenario                                                          | Expected result                                                  |
| ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| User redeems type A, distinct count = 0, Max Distinct = 1         | Allowed. Distinct count → 1                                      |
| User redeems type B after A, distinct count = 1, Max Distinct = 1 | Blocked. RWD018                                                  |
| User redeems type A again, distinct count = 1, Max Distinct = 1   | Allowed (same type, no new slot)                                 |
| User redeems type B after A, Max Distinct = 2                     | Allowed. Distinct count → 2                                      |
| User redeems type C after A+B, Max Distinct = 2                   | Blocked. RWD018                                                  |
| Max Distinct = 2, Group Qty = 1 → save attempt                    | Blocked at save. RWD019                                          |
| Max Distinct = 2, Group Qty = 3 → user redeems 3 units of A       | Allowed (passes Max Distinct=2 as same type; passes Group Qty=3) |
| Reward belongs to 2 groups, each with Max Distinct = 1            | Both groups checked independently; both must pass                |
| `metric` absent from old limit row                                | Coalesced to `quantity`; existing behavior unchanged             |


**Error payload to assert (RWD018):**

```json
{
  "allowed": false,
  "metric": "distinct_reward",
  "title": "Reward type limit reached",
  "limit_count": 1,
  "current_count": 1,
  "remaining": 0
}
```

---

## 7. Business Rules

**Rule 1 — Distinct slot is consumed only by a new type.**
A user's distinct count increments by 1 only when `:reward_id` has never appeared in `reward_redemptions_ledger` for that user within the time window. Re-redemptions of the same type are free of the distinct limit.

**Rule 2 — Max Distinct is user-scoped only.**
`metric = distinct_reward` requires `scope = user`. Total-scope distinct counting is not supported.

**Rule 3 — Conflicting limits are blocked at save, not at redemption.**
If `max_distinct > group_quantity` on the same group at the same user scope, `bff_upsert_reward_group_with_limits` rejects the configuration with `CONFLICTING_GROUP_LIMITS` (RWD019). No contradictory configuration ever reaches the redemption path.

**Rule 4 — All three limits stack independently.**
At redemption time, `fn_check_reward_group_limits` checks all limit rows on all groups the reward belongs to. The member must pass every configured limit. Order: Reward Quota → Group Quantity → Max Distinct.

**Rule 5 — Time windows are independent per limit row.**
A group can have Max Distinct = 1 per year AND Group Qty = 5 per month. The annual distinct window and the monthly quantity window run independently.

**Rule 6 — Group membership is per reward, not per group.**
`reward_master.reward_group_ids UUID[]` stores which groups each reward belongs to. Adding a reward to a group is done on the reward's config, not by editing the group. A reward can belong to 0, 1, or many groups simultaneously.

---

## 8. Business Use Cases (from image reference)

### Use Case 1 — Pick 1 type, any quantity per type

> *"เลือกตั๋วหนัง: Zone A 3 ใบ หรือ Zone B 4 ใบ"*

Member can choose only one zone, but can take multiple seats in that zone.


| Config                 | Value                  |
| ---------------------- | ---------------------- |
| Rewards in group       | Zone A, Zone B, Zone C |
| Max Distinct           | 1 (per user, all time) |
| Group Qty Limit        | — (none)               |
| Reward Quota on Zone A | 3 per user             |
| Reward Quota on Zone B | 4 per user             |


Member redeems Zone A × 3 → allowed (distinct = 1, Zone A quota = 3 ✓). Tries Zone B → blocked (distinct already at max).

---

### Use Case 2 — Pick 1 type, exactly 1 unit

> *"เลือกสายไหมหรือช็อกโกแลตได้อย่างใดอย่างหนึ่ง 1 ชิ้นเท่านั้น"*

Member picks one item from two options; no stacking of the same item.


| Config                      | Value                     |
| --------------------------- | ------------------------- |
| Rewards in group            | Silk Scarf, Chocolate Box |
| Max Distinct                | 1 (per user, all time)    |
| Reward Quota on each reward | 1 per user                |


Member redeems Silk × 1 → allowed. Tries Silk again → blocked by Reward Quota. Tries Chocolate → blocked by Max Distinct.

---

### Use Case 3 — Pick up to M types, any quantity each

> *"มีสินค้า 100 ประเภท สามารถเลือกได้ 3 ประเภท ประเภทละ 3 ชิ้น"*

Member can pick from a large catalog but is limited to 3 distinct types, up to 3 units each.


| Config                      | Value                  |
| --------------------------- | ---------------------- |
| Rewards in group            | 100 rewards            |
| Max Distinct                | 3 (per user, all time) |
| Group Qty Limit             | — (none)               |
| Reward Quota on each reward | 3 per user             |


Member redeems A × 2, B × 3, C × 1 → all allowed (3 distinct types, each within quota). Tries D → blocked (distinct = 3 at max).

---

## 9. Related Features


| Feature            | Connection                                                                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rewards            | Reward Groups enforce cross-reward limits on top of individual reward configs. See [rewards.md](rewards.md) for per-reward quota and eligibility. |
| Transaction Limits | `transaction_limits` stores both per-reward and per-group limits. The `metric` column is what differentiates Max Distinct from Quantity.          |
| Currency (Points)  | Points are deducted per-reward at the individual reward's configured cost. Group limits do not affect points pricing.                             |
| AMP Workflows      | Campaign-visibility rewards can be pushed into groups; group limits enforce redemption caps across push-delivered reward types.                   |


