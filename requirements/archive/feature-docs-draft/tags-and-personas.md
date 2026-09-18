# Feature Guide: Tags & Personas

## 1. Overview

Tags and personas are two complementary classification systems that let merchants segment their customer base beyond tiers. Personas represent a member's business profile — Corporate, Student, Distributor — and each member can have at most one. Tags are behavioral markers — VIP, At Risk, Early Adopter — and a member can carry unlimited tags. Together they form two of the four dimensions (alongside tier and user_type) that other features use for eligibility filtering and dynamic pricing.

Personas are organized into groups, and each group can optionally specify a user_type (buyer or seller). When a member is assigned a persona, the system automatically updates their user_type to match the group's setting. This means persona assignment doubles as a user_type management tool — a merchant doesn't need to manually set buyer/seller status if their persona groups already encode it.

Tags serve a different purpose: flexible, additive labeling for behavioral attributes and marketing segmentation. A member tagged "VIP" and "Influencer" can be targeted by campaigns, granted special reward eligibility, or routed to priority support. Unlike personas, tags have no hierarchy and no side effects on other fields.

## 2. Key Concepts

**Persona** — A member's primary business classification. Stored as `persona_id` on the user account. Each member has zero or one persona. Example: "SME" under the "Corporate Members" group.

**Persona Group** — A parent category that contains personas and optionally defines a `user_type`. All personas in a group share the group's user_type behavior. Example: "Corporate Members" (user_type=seller) contains "SME", "Corporation", "Enterprise".

**Tag** — An independent label attached to a member. Many-to-many: a member can have any number of tags, and a tag can be assigned to any number of members. Example: "VIP", "At Risk", "Frequent Buyer".

**User Type** — An enum on user_accounts with values `buyer` or `seller`. Persona assignment can auto-update this value based on the persona group's configuration. Removing a persona does not revert user_type.

**Merchant Isolation** — All personas, persona groups, and tags are scoped to a single merchant. Cross-merchant assignment is blocked at the function level.

**Idempotent Operations** — Adding a tag that already exists returns success without creating a duplicate. Removing a tag that isn't assigned returns success. Duplicate-safe by design.

**Active Status** — Personas, persona groups, and tags each have an `active_status` flag. Inactive items cannot be newly assigned but existing assignments are not removed when an item is deactivated.

## 3. Configuration Reference

### Persona Group

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Group name | Display name of the category | "Corporate Members" | Required |
| Description | Purpose explanation | "B2B customer segments" | Empty |
| User type | Auto-assigned user_type for personas in this group | `seller` | null (no change) |
| Active status | Whether group's personas can be assigned | true | true |
| Config (jsonb) | Reserved for future group-level settings | `{}` | `{}` |

### Persona

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Persona name | Display name shown to members and admins | "SME" | Required |
| Description | What this persona represents | "Small/medium enterprises" | Empty |
| Group | Parent persona group (required) | "Corporate Members" | Required |
| Image | Avatar shown in signup persona selector | CDN URL | null |
| Active status | Whether this persona can be assigned | true | true |
| Config (jsonb) | Reserved for persona-specific settings | `{}` | `{}` |

### Tag

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Tag name | Identifier for the tag | "VIP" | Required |
| Description | What this tag represents | "High-value customer" | Empty |
| Active status | Whether this tag can be assigned | true | true |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Persona Group Settings | `/persona` | `bff_get_persona_structure()`, `upsert_persona_group_with_personas()` |
| Customer 360 (search) | `/customer-360` | Customer search |
| Customer 360 (detail) | `/customer-360/{userId}` | User profile with persona/tag data |

### 4a. Manage Persona Groups and Personas

1. Open **Persona Group Settings** — page displays existing groups as collapsible cards
2. Click **"+ Add persona group"** — new empty card appends in expanded state
3. Enter group name (required) and optionally select user_type (`buyer`, `seller`, or none)
4. Click **"+ Add persona"** within the group card — new persona row appears
5. Enter persona name, optionally upload an image (avatar for member-facing selector)
6. Reorder personas using arrow buttons if needed
7. Click **"Save"** — calls `upsert_persona_group_with_personas()` → page refreshes via RSC

### 4b. Edit or Delete Groups and Personas

1. From **Persona Group Settings**, click the edit icon on a group card → card expands with editable fields
2. Modify group name, user_type, or persona rows → click **"Save"**
3. To delete a persona: remove the row from the expanded card and save
4. To delete a group: click the delete icon → confirmation dialog. Deletion is blocked if the group still contains personas — the RPC returns an error with the count of remaining personas
5. Individual personas can also be deleted via `admin_delete_persona()`

### 4c. Assign Persona or Tags to a Member

1. Navigate to **Customer 360** → search for the member
2. Open the member's detail page — profile sidebar shows current persona and tags
3. Use the edit profile panel to assign/change persona or add/remove tags
4. Persona assignment calls `assign_persona()` — automatically updates user_type if the group specifies one
5. Tag assignment calls `assign_tag()` with action `add` or `remove`

### 4d. Common Admin Mistakes

- Creating a persona group without user_type when the business requires buyer/seller distinction — members assigned personas from this group keep their existing user_type
- Deleting a persona that members are currently assigned to — the persona_id on their account becomes a dangling reference
- Assuming deactivating a persona group removes existing assignments — it only prevents new assignments

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Signup Drawer (persona step) | Bottom-sheet on any page | `bff-auth-complete` → `missing_data` payload |
| Profile Page | `/profile` | `get_user_summary()` |
| Edit Profile Drawer | Bottom-sheet on `/profile` | `bff_get_user_profile_template(mode='edit')` |

### 5a. Persona Selection During Signup

1. After authentication, the signup drawer advances through form steps: **persona** → default fields → custom fields → PDPA
2. The persona step renders a **PersonaSelector** — a 4-column avatar grid grouped by persona group name
3. Each avatar shows the persona image (or first letter fallback) with the persona name below
4. Member taps one avatar → ring highlight + checkmark appears on the selected persona
5. Only one persona can be selected. Tapping another replaces the selection.
6. The persona step is skipped entirely if the merchant does not use the persona system
7. On final form submission, `bff_save_user_profile` persists the selected persona_id

### 5b. Persona on Profile

1. The member's assigned persona is part of their profile data returned by `get_user_summary()`
2. The Edit Profile drawer fetches `bff_get_user_profile_template(mode='edit')` — if the template includes persona data, the member can view or change their persona
3. Members do not manage their own tags — tags are admin-assigned or API-assigned only
4. Tags affect what the member sees indirectly: other features (rewards, missions) use tags as eligibility filters, so a tagged member may see different content than an untagged one

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Personas are your customers' business profiles — Corporate, Student, Distributor. Each customer gets one. Tags are flexible labels — VIP, At Risk, Influencer — and customers can have as many as needed. Together, they let you target rewards, pricing, and campaigns to the right segments."

**Common questions:**

| Question | Answer |
|---|---|
| "What's the difference between persona and tag?" | Persona = business profile (one per member, can change user_type). Tag = behavioral label (unlimited per member, no side effects). |
| "A member's user_type changed unexpectedly" | Check if a persona was recently assigned from a group with a user_type setting. Persona assignment auto-updates user_type. |
| "Can we undo a user_type change?" | Removing the persona does not revert user_type. You must manually update user_type or assign a persona from a group with the desired user_type. |
| "A tag was assigned twice" | Not possible — the system prevents duplicates. The second assignment returns success without creating a new record. |
| "Deactivated a persona but members still have it" | Deactivating prevents new assignments only. Existing assignments persist until explicitly changed. |
| "Member didn't see persona selection during signup" | Merchant may not have the persona system enabled, or all persona groups are inactive. Check `bff_get_persona_structure()` returns data. |

**Config mistakes → fix:**

| Mistake | Symptom | Fix |
|---|---|---|
| Persona group has no user_type set | Members assigned personas keep their old user_type | Set user_type on the group if buyer/seller distinction is needed |
| All persona groups deactivated | Persona step skipped in signup, no personas assignable | Reactivate at least one group |
| Persona deleted while members assigned to it | Dangling `persona_id` on user accounts | Reassign affected members to a new persona or set to null |

### 6b. For Marketing

**Value proposition:** Tags and personas add two segmentation dimensions on top of tiers. Personas classify members by business profile (B2B vs B2C, student vs corporate), while tags capture behavioral signals (engagement level, risk status, influencer potential). Both feed into the eligibility and dynamic pricing engines across rewards, missions, and earn rules.

**Segmentation use cases:**
1. **Persona-based pricing** — "Corporate" members pay 60 points for a reward, "Student" members pay 40 points (via dynamic pricing conditions on the reward)
2. **Tag-driven campaigns** — Target "At Risk" tagged members with retention rewards; target "VIP" tagged members with exclusive early-access offers via AMP workflows
3. **Combined targeting** — Reward eligibility restricted to "Corporate" persona + "VIP" tag = only high-value business customers qualify
4. **Lifecycle management** — Tag new signups as "New Customer", auto-tag based on purchase patterns, retarget "Dormant" tagged members
5. **B2B user type automation** — Create persona groups with `user_type=seller` for distributors and resellers. When a member selects their business persona during signup, they're automatically classified as a seller without manual intervention

**When to use persona vs. tag:**

| Use case | Persona | Tag |
|---|---|---|
| Business type classification (SME, Corporation, Student) | Yes | — |
| Customer value indicator (VIP, High Spender) | — | Yes |
| Lifecycle stage (New, Active, Dormant, Churned) | — | Yes |
| Organization role (Distributor, Reseller, Franchise) | Yes | — |
| Behavioral signal (Early Adopter, Influencer, At Risk) | — | Yes |

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Assign persona from group with `user_type=seller` | Member's user_type changes to `seller` |
| Assign persona from group with `user_type=null` | Member's user_type unchanged |
| Remove persona (set to null) | `persona_id` cleared, user_type unchanged |
| Add tag to member | `user_tags` record created |
| Add same tag again | Success response, no duplicate record |
| Remove tag from member | `user_tags` record deleted |
| Remove tag not assigned | Success response, no error |
| Assign inactive persona | Error returned, assignment blocked |
| Assign tag from different merchant | Error: "Tag belongs to different merchant" |
| Deactivate persona group | Existing assignments persist, new assignments blocked |

**Business rules as assertions:**

- ASSERT: A member has at most one `persona_id` at any time
- ASSERT: A member can have unlimited tags (no upper bound enforced)
- ASSERT: Persona assignment from a group with user_type updates `user_accounts.user_type`
- ASSERT: Persona removal sets `persona_id = null` but does not change `user_type`
- ASSERT: Tag add is idempotent — duplicate calls produce exactly one `user_tags` record
- ASSERT: Tag remove is idempotent — removing a non-existent assignment returns success
- ASSERT: Cross-merchant persona/tag assignment is rejected
- ASSERT: Inactive persona/tag assignment is rejected
- ASSERT: Deleting a persona group with existing personas is blocked

**Cross-feature scenarios to test:**

- Assign persona → check reward eligibility updates (persona is an eligibility dimension)
- Assign persona → check dynamic pricing changes (persona is a pricing dimension)
- Add tag → check reward eligibility updates (tags are an eligibility dimension)
- Change persona from group A (seller) to group B (buyer) → verify user_type changes to buyer
- Remove persona → verify user_type stays at last-set value
- Signup flow: select persona during registration → verify persona_id saved on user_accounts
- Signup flow: merchant without persona system → verify persona step is skipped

## 7. Business Rules

**Rule:** Each member has at most one persona. Assigning a new persona replaces the existing one.
**Example:** Member has "SME" persona → assigned "Corporation" → member now has "Corporation", "SME" is gone.

**Rule:** Persona groups optionally define a `user_type`. When a persona is assigned, the member's user_type updates to the group's value if one is set.
**Example:** "Corporate Members" group has `user_type=seller`. Assigning any persona from this group changes the member to `seller`.

**Rule:** Removing a persona (setting to null) does not revert user_type. The last user_type set by a persona assignment persists.
**Example:** Member was `buyer` → assigned "SME" (seller group) → became `seller` → persona removed → member stays `seller`.

**Rule:** Members can have unlimited tags. Tags are independent — no hierarchy or grouping.
**Example:** Member can simultaneously be tagged "VIP", "Influencer", "Early Adopter", "Frequent Buyer".

**Rule:** Tag operations are idempotent. Adding an existing tag or removing a non-existent tag returns success without error.
**Example:** `assign_tag(user, vip_tag, 'add')` called twice → one `user_tags` record, two success responses.

**Rule:** All personas, groups, and tags are merchant-scoped. Cross-merchant assignment is blocked at the function level.
**Example:** Tag belonging to Merchant A cannot be assigned to a user belonging to Merchant B.

**Rule:** Deactivating a persona, group, or tag prevents new assignments but does not remove existing ones.
**Example:** Deactivating "VIP" tag → members who already have it keep it, but no new members can receive it.

**Rule:** A persona group cannot be deleted while it still contains personas. Delete or reassign all child personas first.
**Example:** Attempting to delete "Corporate Members" with 3 personas → error response with count.

**Rule:** Persona and tag names must be unique per merchant.
**Example:** Two tags named "VIP" under the same merchant → blocked by unique constraint.

## 8. Related Features

| Feature | Connection to Tags & Personas |
|---|---|
| Rewards | Personas and tags are eligibility dimensions and dynamic pricing dimensions. See `Reward.md`. |
| Tier | Tier + persona + tags together form the segmentation stack. Tier evaluations can factor in persona. See `Tier.md`. |
| Currency | Earn rules can use persona for personalized earn factors (e.g., Corporate earns 2x). See `Currency.md`. |
| Forms | Profile form includes persona selection step during signup. Persona-aware conditional fields can show/hide based on selected persona. See `Forms.md`. |
| Missions | Mission eligibility can be filtered by persona and tags. See `Mission.md`. |
| AMP Workflows | Automation workflows can use persona/tag as audience conditions for targeted campaigns. See `AMP - Rule Based.md`. |
