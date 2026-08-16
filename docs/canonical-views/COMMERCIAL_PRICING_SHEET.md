# Commercial Pricing Sheet

Canonical billable-unit view of Rocket CRM. Written from the Product Feature Catalog — not an exhaustive feature list.

**Contract:** `workflows/canonical-views/REFERENCE.md`  
**Voice:** `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md`  
**Language:** EN  
**Prices:** blank (`—`) until a sales run fills them from `list-prices.json` with a member scale  
**Table grammar:** Feature · Unit · Price (Merz / Rocket Deck)  
**Sections** = modules. **Rows** = plan grouping (Core / Advanced) and/or fee model.

Use with the [Features Summary](./FEATURES_SUMMARY.md) when the buyer needs coverage detail.

---

## Loyalty

### Loyalty Core (`loyalty_core`)

| Feature | Unit | Price |
| --- | --- | --- |
| Loyalty Core | Per month | — |

- **Sign up** with LINE / phone OTP, including a custom signup form
- **Points** balance, expiry, a basic earn rate, and a different rate by member tier
- **Earn channels** purchase sync, marketplace, QR/code, receipt upload, and manual adjust
- **Rewards** catalog and redemption, who can redeem, and promo codes on redeem
- **Burn** points to a discount at checkout — set how many points equal a discount
- **Member tiers** with configurable conditions for upgrade and maintenance
- **Personas and tags** for targeting and eligibility
- **Lifecycle automations** birthday, signup, anniversary, and tier-change awards
- **Member app UI CMS** edit the screens members see (homepage, banners, points, menus, featured rewards)
- **Admin portal** configure loyalty from admin — reward codes, tier earn rates, space settings, privacy consent (PDPA), languages, and customer import
- **Front Line** store staff look up a member and help them — adjust points, push a reward, or mark a reward used
- **Reports** 30+ in the standard admin portal covering Members, Member 360, Redemptions, Transactions, Campaigns, and more

### Loyalty Advanced (additional to Core) (`loyalty_advanced`)

| Feature | Unit | Price |
| --- | --- | --- |
| Loyalty Advanced (additional to Core) | Per month | — |

- **Advanced earn rates** different rates per channel, store group, or product category — and/or multipliers such as double points on a category or for a member type
- **Advanced rewards** flash rewards open for a short window, and one shared quota across a set of rewards
- **Advanced tiers** evaluation windows and separate ladders by persona
- **Surveys** collect feedback and extra member data with survey-style forms
- **Member types** such as student or corporate — used in rules and earn rates
- **Segments** members by custom conditions or RFM, then LINE or SMS that segment

### Campaigns (`loyalty_campaigns`)

| Feature | Unit | Price |
| --- | --- | --- |
| Campaigns | Per campaign unit / month | — |

- **Missions** complete goals in any order, or step-by-step milestone missions
- **Referral** members invite friends with a code — both sides earn when the rules are met
- **Check-in** daily or weekly check-in streaks that earn rewards
- **Spin wheel** members spend points to spin for a random prize
- **Lucky draw** members spend points to enter, then you draw the winners

*One campaign unit = one campaign type enabled for the month — Mission, Referral, Check-in, Spin wheel, or Lucky draw*

### Receipt AI / OCR auto-approve (`loyalty_receipt_auto_approve`)

| Feature | Unit | Price |
| --- | --- | --- |
| Receipt AI / OCR auto-approve | Per receipt | — |

- **Receipt AI** auto-approve uploads with OCR

### Open API (`loyalty_open_api`)

| Feature | Unit | Price |
| --- | --- | --- |
| Open API | Per month | — |

- **Open API** connect your POS, app, or website to Rocket — members, purchases, points, redemptions, and assets. Your system stays the source of truth; Rocket stays the loyalty ledger.

### SMS (`loyalty_sms`)

| Feature | Unit | Price |
| --- | --- | --- |
| SMS | Per month | — |

- **SMS** extra messages at 0.25 THB each

*{{sms_included}} messages included each month at this member scale*

---

## Shopify

### Shopify loyalty plugin (`loyalty_shopify`)

| Feature | Unit | Price |
| --- | --- | --- |
| Shopify loyalty plugin | Per month | — |

*A loyalty widget on your Shopify store that also ties to non-Shopify channels, plus native Shopify integration.*

- **Shopify orders** members earn points from paid Shopify orders automatically
- **Shopify widget** member loyalty status on the storefront
- **Shopify burn** points to a discount in checkout
- **Member matching** Shopify customers linked to Rocket members (email, phone, or Shopify id)

---

## Marketing Automation

### Workflows (`marketing_automation_core`)

| Feature | Unit | Price |
| --- | --- | --- |
| Workflows | Per month | — |

- **Workflows** multi-step journeys that message members and run loyalty actions
- **LINE Flex** design Flex cards and use them in those workflow message steps
- **Audiences** member groups that trigger those workflows

*This price covers 10 active workflows*

### AI (`marketing_automation_advanced`)

| Feature | Unit | Price |
| --- | --- | --- |
| AI | Per month | — |

- **AI decisioning** chooses ACT, WAIT, or SKIP per member from your goals and limits
- **AI analysis** recommends what to change in workflows and agents

---

## Customer Service

### Customer Service Software (`customer_service_core`)

| Feature | Unit | Price |
| --- | --- | --- |
| Customer Service Software | Per seat / month | — |

- **Omnichannel inbox** every connected channel in one queue
- **Chat and voice** on the same customer record
- **Quick replies** and knowledge search for agents mid-conversation
- **Routing** send conversations to the right queue, team, or agent by rule
- **Knowledge base** one source of service answers for agents and AI
- **Service analytics** volume, response time, CSAT

### AI Customer Service Agent (`customer_service_ai`)

| Feature | Unit | Price |
| --- | --- | --- |
| AI Customer Service Agent | Per resolved case | — |

- **AI service agent** answers customers under your tone and escalation rules
- **Agent operating procedures (AOPs)** the steps your AI follows, including actions it can take for the customer mid-conversation
- **Live assist** suggested replies for agents mid-conversation
- **Chatbot flows** automated conversations before or beside human agents
- **Quality scoring** score human and AI conversations, with Supervisor AI reviewing both
