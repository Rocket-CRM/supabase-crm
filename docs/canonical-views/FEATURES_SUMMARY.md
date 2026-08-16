# Features Summary

Canonical feature-group summary for Rocket CRM. Written from the Product Feature Catalog — **full coverage** for RFP / competitor compare, in sales shorthand (not a catalog photocopy).

**Contract:** `workflows/canonical-views/REFERENCE.md`  
**Voice:** `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md`  
**Language:** EN  
**Companion:** [Commercial Pricing Sheet](./COMMERCIAL_PRICING_SHEET.md) (billable units; clustered highlights)  
**Sections** = modules (H2). **Rows** = feature groups (H3). HTML export: one ModuleBlock per module.

Each bullet is one catalog feature: a sales-facing name + one shorthand sentence — except the fold list below.

**Omit from this view** (catalog stays): tickets, event promotions. Store attributes are explained on earn rates, not as their own line. PDPA, languages, and Customer 360 fold into **Admin portal and reports** (config list + Member 360 as a key area).

---

## Loyalty

### Signup & login (`platform.signup`)

| Feature group | Capabilities |
| --- | --- |
| Signup & login | (see bullets) |

- **Login with LINE or phone OTP**
  Members sign in with LINE, a phone OTP, or both — you choose which methods to allow.
- **Signup profile completion**
  Require the profile fields you need after login before members enter the app.
- **Signup on your own website**
  Run Rocket signup on your own site so members join without leaving your brand.
- **Custom signup form**
  Choose which fields members answer at signup or when they finish their profile.

### Points (`loyalty.currency`)

| Feature group | Capabilities |
| --- | --- |
| Points | (see bullets) |

- **Points balance**
  One interchangeable points balance members spend on rewards or discounts.
- **Points expiry**
  Expire points on a rolling period after earn (e.g. 12 months) or on fiscal periods, with a minimum validity so late-period earns are not wiped immediately.
- **Basic earn rate**
  One flat rate for how spending turns into points (for example 100 THB = 1 point).
- **Advanced earn rates**
  Different rates by sales channel, store or store group, or product category — and/or a multiplier such as double points on skincare or for student members.
- **Bonus point multipliers**
  Multiply points for selected products, categories, or member types — e.g. double points on skincare.

### Earn channels (`loyalty.earn`)

| Feature group | Capabilities |
| --- | --- |
| Earn channels | (see bullets) |

- **Member Earn page**
  Choose which earn actions appear on the member Earn page — e.g. upload a receipt, claim a marketplace order, scan a QR.
- **Earn from purchase sync**
  Points post automatically when a purchase arrives from your POS or online store.
- **Earn from marketplace orders**
  Members claim or match a Shopee, Lazada, or TikTok Shop order to earn points. Shopify orders earn through the Shopify plugin.
- **Earn from QR / code scan**
  Members scan a QR or enter a code on a product, receipt, or poster.
- **Earn from receipt upload**
  Members photograph a paper receipt; points are awarded after staff review.
- **Receipt AI / OCR auto-approve**
  Auto-approve receipt uploads with AI/OCR, optionally from line items (metered per receipt).
- **Earn from activity proof**
  Members upload a photo as proof of a non-purchase activity, then earn after review.
- **Manual points adjust**
  Staff add or correct points in Front Line for service recovery, mistakes, or migrations.
- **Earn via Open API**
  Your systems grant points by calling Rocket's API.

### Rewards (`loyalty.reward`)

| Feature group | Capabilities |
| --- | --- |
| Rewards | (see bullets) |

- **Reward catalog and redemption**
  Members browse rewards and redeem them for points.
- **Dynamic reward pricing**
  The same reward can cost different points for different members.
- **Reward eligibility**
  Control who can see or redeem a reward by tier, persona, time window, and similar rules.
- **Reward groups and shared limits**
  Limit how many rewards a member can take from a set that shares one quota.
- **Flash rewards**
  Publish a reward for a short window — minutes or a drop — so members redeem before it disappears.
- **Promo codes on redeem**
  Issue a unique promo or coupon code when a member redeems.
- **Admin push and claim links**
  Push a reward to one member, or distribute it with a claim link or QR.

### Points-to-discount (`loyalty.burn`)

| Feature group | Capabilities |
| --- | --- |
| Points-to-discount | (see bullets) |

- **Points-to-discount at checkout**
  Set how many points equal a money discount at checkout — the default rate for the program.
- **Points-to-discount by tier**
  Different checkout discount rates by member tier, or turn discount off for some tiers.

### Tiers (`loyalty.tier`)

| Feature group | Capabilities |
| --- | --- |
| Tiers | (see bullets) |

- **Member tiers**
  A tier ladder members progress through, each tier showing its own benefits in the app.
- **Tier upgrade conditions**
  Set what members must meet to move up — for example points earned or amount spent.
- **Tier maintenance**
  Keep a tier once earned, or require members to re-qualify each period.
- **Tier evaluation windows**
  Measure progress on a calendar year or rolling months, and choose when upgrades apply.
- **Earn rates by tier**
  A different earn rate based on the member's current tier.
- **Separate ladders by persona**
  Different member-tier programs for different personas or member types — e.g. student vs corporate.

### Campaigns (`loyalty.campaign`)

| Feature group | Capabilities |
| --- | --- |
| Campaigns | (see bullets) |

- **Missions — standard**
  Members complete several goals in any order to unlock a reward.
- **Missions — milestone**
  Members finish ordered steps — step 1 before step 2 unlocks.
- **Referral**
  Members invite friends with a code; both sides can earn when the rules are met.
- **Check-in**
  Daily or weekly check-in to build streaks and earn rewards.
- **Spin wheel**
  Members spend points or tickets to spin for a random prize.
- **Lucky draw**
  Members spend points or tickets to enter; you draw and announce the winners offline.

### Customer profile and forms (`loyalty.forms`)

| Feature group | Capabilities |
| --- | --- |
| Customer profile and forms | (see bullets) |

- **Profile fields**
  Choose which profile fields you collect (email, phone, name, address, and similar).
- **Custom profile fields**
  Add your own fields beyond the default set.
- **Surveys**
  Run survey-style forms for feedback and extra member data.

### Lifecycle automations (`loyalty.lifecycle`)

| Feature group | Capabilities |
| --- | --- |
| Lifecycle automations | (see bullets) |

- **Signup automation**
  Automatically award points, rewards, or tags when members finish signup.
- **Birthday automation**
  Automatically award points or other outcomes around a member's birthday.
- **Anniversary automation**
  Automatically award outcomes on membership anniversary.
- **Tier-change automation**
  Automatically award outcomes when a member upgrades or downgrades.

### Segmentation (`loyalty.persona`)

| Feature group | Capabilities |
| --- | --- |
| Segmentation | (see bullets) |

- **Tags and personas**
  Classify members for eligibility, automation, and reporting.
- **Member types**
  Types such as student or corporate, used in rules, earn rates, and tier ladders.
- **Persona entitlements**
  Extra access or benefits for a persona beyond normal tags.
- **LINE or SMS to a segment**
  Send a LINE or SMS to members you picked with custom conditions or RFM — the same messaging engine as Marketing Automation.

### Store network (`loyalty.store`)

| Feature group | Capabilities |
| --- | --- |
| Store network | (see bullets) |

- **Store / outlet directory**
  A directory of outlets used for earning, redemption, and reporting.

### Member app UI CMS (`platform.experience`)

| Feature group | Capabilities |
| --- | --- |
| Member app UI CMS | (see bullets) |

- **Member app UI CMS**
  Edit the member-app screens from a CMS — banners, points, tier progress, featured rewards, menus — without engineering work.

### Admin portal and reports (`platform.governance`)

| Feature group | Capabilities |
| --- | --- |
| Admin portal and reports | (see bullets) |

- **Admin portal**
  Configure the loyalty program from admin: reward codes, tier earn rates, space settings, privacy consent (PDPA), languages, and team roles.
- **Reports**
  More than 30 reports in the standard admin portal. Key areas: Members, Member 360, Redemptions, Transactions, Campaigns.

### Front Line (`loyalty.frontline`)

| Feature group | Capabilities |
| --- | --- |
| Front Line | (see bullets) |

- **Front Line**
  Store staff look up a member and help them on the spot: adjust points, push a reward, mark a reward used, update profile, or change mobile and persona.

### RFM and funnels (`loyalty.analytics`)

| Feature group | Capabilities |
| --- | --- |
| RFM and funnels | (see bullets) |

- **RFM scoring**
  Score members by how recently, how often, and how much they buy — for targeting.
- **Funnel stages**
  Define journey stages and report conversion between them.

### Admin, data operations, and integrations (`loyalty.ops`)

| Feature group | Capabilities |
| --- | --- |
| Admin, data operations, and integrations | (see bullets) |

- **Customer import / export**
  Bulk import or export member profiles for migrations and operations.
- **Bulk points import**
  Bulk load points for migrations or campaigns.

### Open API & integrations (`loyalty.integrations`)

| Feature group | Capabilities |
| --- | --- |
| Open API & integrations | (see bullets) |

- **Open API**
  Connect your POS, app, or website to Rocket — members, purchases, points, redemptions, and assets. Your system stays the source of truth; Rocket stays the loyalty ledger.

---

## Shopify

### Shopify loyalty plugin (`loyalty.storefront`)

| Feature group | Capabilities |
| --- | --- |
| Shopify loyalty plugin | (see bullets) |

A loyalty widget on your Shopify store that also ties to non-Shopify channels, plus native Shopify integration.

- **Earn from Shopify orders**
  Members earn points from paid Shopify orders automatically.
- **Shopify loyalty widget**
  Show member loyalty status on the Shopify storefront.
- **Shopify points-to-discount**
  Let members burn points to a discount in Shopify checkout.
- **Shopify member matching**
  Shopify customers are linked to Rocket members by Shopify id, email, or phone.

---

## Marketing Automation

### Multi-step workflows (`marketing_automation.workflows`)

| Feature group | Capabilities |
| --- | --- |
| Multi-step workflows | (see bullets) |

- **Multi-step workflows**
  Fixed journeys that wait, branch, send messages, and run loyalty actions.
- **LINE Flex messages**
  Design LINE Flex cards and use them as message steps in those workflows.
- **Audience automation**
  Dynamic or static audiences whose join/leave can trigger those workflows.

### AI decisioning (`marketing_automation.ai_decisioning`)

| Feature group | Capabilities |
| --- | --- |
| AI decisioning | (see bullets) |

- **AI decisioning agent**
  You set goals, allowed actions, and limits; the agent chooses ACT, WAIT, or SKIP per member.

### AI analysis (`marketing_automation.ai_analysis`)

| Feature group | Capabilities |
| --- | --- |
| AI analysis | (see bullets) |

- **AI analysis and recommendations**
  Analyze workflow and agent results, then recommend what marketers should change next.

---

## Customer Service

### Omnichannel inbox and connectivity (`customer_service.connectivity`)

| Feature group | Capabilities |
| --- | --- |
| Omnichannel inbox and connectivity | (see bullets) |

- **Omnichannel inbox**
  One inbox across connected channels, with one customer record.
- **Channel connectors**
  Connect messaging apps, email, web, SMS, marketplaces, and related surfaces.
- **Phone numbers**
  Provision and manage numbers used for voice and SMS.

### Chat and voice (`customer_service.chat_voice`)

| Feature group | Capabilities |
| --- | --- |
| Chat and voice | (see bullets) |

- **Chat**
  Async chat with full history and agent tools.
- **Voice**
  Voice contacts with the same customer context used for chat.

### Agent productivity (`customer_service.agent_productivity`)

| Feature group | Capabilities |
| --- | --- |
| Agent productivity | (see bullets) |

- **Quick replies**
  Approved reply snippets for faster, consistent answers.
- **Knowledge search**
  Agents search the knowledge base during a live conversation.
- **Live assist**
  Suggested replies and context for agents mid-conversation.

### Routing and chatbot workflows (`customer_service.routing_workflows`)

| Feature group | Capabilities |
| --- | --- |
| Routing and chatbot workflows | (see bullets) |

- **Routing**
  Route conversations to queues, skills, or agents based on rules.
- **Chatbot flows**
  Visual chatbot workflows before or beside human agents.

### Service analytics (`customer_service.analytics`)

| Feature group | Capabilities |
| --- | --- |
| Service analytics | (see bullets) |

- **Service analytics**
  Volume, response times, CSAT, containment, and agent productivity.

### AI service agent (`customer_service.ai_agent`)

| Feature group | Capabilities |
| --- | --- |
| AI service agent | (see bullets) |

- **AI service agent**
  Brand-configured AI handles or assists conversations under your tone, language, and escalation rules.

### AOPs, knowledge, and customer actions (`customer_service.aop_actions`)

| Feature group | Capabilities |
| --- | --- |
| AOPs, knowledge, and customer actions | (see bullets) |

- **Agent operating procedures (AOPs)**
  Per-intent procedures the AI follows when resolving issues.
- **Knowledge base**
  Service knowledge with citations for agents and AI.
- **Customer actions**
  Permitted lookups, loyalty actions, or integrations from service flows.

### Supervisor AI and quality scoring (`customer_service.supervisor_ai`)

| Feature group | Capabilities |
| --- | --- |
| Supervisor AI and quality scoring | (see bullets) |

- **Quality scoring**
  Score human and AI conversations for quality, policy, and coaching.
- **Supervisor AI**
  Reviews AI and human cases, then feeds what it finds back into prompts and AOPs.
