# Mockup lookup — slide id → embed marker

Dynamic slides embed their mockup id: `[asset:mockup;id=<mockupId>;title=<caption+with+plus>]` (no pitch for this run).
Static slides (no mockup id) embed as `[asset:fixed_diagram;slide=<slideId>]`.

| Slide id | Title | Embed |
|---|---|---|
| `company.title` | Title — Rocket Agentic B2C CRM | `[asset:fixed_diagram;slide=company.title]` |
| `company.about` | About Rocket | `[asset:fixed_diagram;slide=company.about]` |
| `company.our-services` | Our Services | `[asset:fixed_diagram;slide=company.our-services]` |
| `company.differentiation` | Rocket's differentiation | `[asset:fixed_diagram;slide=company.differentiation]` |
| `loyalty.diagram.modularity` | Modularity (rule engine) | `[asset:fixed_diagram;slide=loyalty.diagram.modularity]` |
| `company.thank-you` | Thank you | `[asset:fixed_diagram;slide=company.thank-you]` |
| `company.martech-report-2025` | Number 1 most likely to use in 2025 | `[asset:fixed_diagram;slide=company.martech-report-2025]` |
| `company.events` | Leading innovation in Thailand | `[asset:fixed_diagram;slide=company.events]` |
| `loyalty.basic.rewards` | Feature on mobile — rewards flow | `[asset:mockup;id=loyalty.core.rewards.list;title=...]` |
| `loyalty.basic.rewards-screens` | Rewards — member screens | `[asset:mockup;id=loyalty.core.rewards.list;title=...]` · `[asset:mockup;id=loyalty.core.rewards.detail;title=...]` · `[asset:mockup;id=loyalty.core.rewards.slip;title=...]` |
| `loyalty.basic.packages` | Feature on mobile — packages flow | `[asset:fixed_diagram;slide=loyalty.basic.packages]` |
| `loyalty.basic.signup` | Sign up — LINE OA to consent | `[asset:fixed_diagram;slide=loyalty.basic.signup]` |
| `loyalty.basic.home` | Feature on mobile — loyalty home | `[asset:mockup;id=loyalty.core.home.home;title=...]` |
| `loyalty.basic.profile` | Feature on mobile — member profile | `[asset:mockup;id=loyalty.core.profile.home;title=...]` |
| `loyalty.basic.upload-receipt` | Feature on mobile — upload receipt | `[asset:mockup;id=loyalty.core.earn.upload;title=...]` |
| `loyalty.basic.pos-earn` | EARN : In-store purchases, from any POS | `[asset:fixed_diagram;slide=loyalty.basic.pos-earn]` |
| `loyalty.basic.marketplace-earn` | Feature on mobile — marketplace earn | `[asset:mockup;id=loyalty.core.earn.marketplace;title=...]` |
| `loyalty.basic.shopify-plugin` | Shopify plugin vs order sync | `[asset:fixed_diagram;slide=loyalty.basic.shopify-plugin]` |
| `loyalty.basic.tiers` | Tiers & Benefits | `[asset:mockup;id=loyalty.core.tier.benefit;title=...]` |
| `loyalty.campaigns.missions` | Missions | `[asset:mockup;id=loyalty.campaign.your-brand-missions.cover;title=...]` |
| `loyalty.campaigns.leaderboard` | Leaderboards | `[asset:mockup;id=loyalty.campaign.your-brand-topspender.cover;title=...]` |
| `loyalty.campaigns.luckydraw` | Mass Lucky Draw | `[asset:mockup;id=loyalty.campaign.your-brand-lucky-draw.cover;title=...]` |
| `loyalty.campaigns.spinwheel` | Spin the Wheel | `[asset:mockup;id=loyalty.campaign.your-brand-spin-wheel.cover;title=...]` |
| `loyalty.campaigns.checkin` | Daily Check-in | `[asset:mockup;id=loyalty.campaign.your-brand-checkin.cover;title=...]` |
| `loyalty.campaigns.survey` | Surveys | `[asset:mockup;id=loyalty.campaign.your-brand-survey.cover;title=...]` |
| `loyalty.campaigns.referral` | Referral | `[asset:mockup;id=loyalty.campaign.your-brand-invite.cover;title=...]` |
| `loyalty.reports.control-center` | Reports — Exec Overview | `[asset:mockup;id=loyalty.admin.reports-exec.overview;title=...]` |
| `loyalty.reports.members` | Report — Members | `[asset:mockup;id=loyalty.admin.reports-members.overview;title=...]` |
| `loyalty.reports.customer-360` | Report — Customer 360 | `[asset:mockup;id=loyalty.admin.customer-360.member;title=...]` |
| `loyalty.reports.transactions` | Report — Transactions | `[asset:mockup;id=loyalty.admin.reports-transactions.overview;title=...]` |
| `loyalty.reports.points-liability` | Report — Points | `[asset:mockup;id=loyalty.admin.reports-points.overview;title=...]` |
| `loyalty.reports.rewards-redemption` | Report — Redemptions | `[asset:mockup;id=loyalty.admin.reports-redemptions.overview;title=...]` |
| `loyalty.reports.rfm` | Report — RFM | `[asset:mockup;id=loyalty.admin.reports-rfm.overview;title=...]` |
| `loyalty.admin.display-settings` | Admin — Display Settings | `[asset:mockup;id=loyalty.admin.display-settings.core;title=...]` |
| `loyalty.admin.rewards` | Admin — Rewards | `[asset:mockup;id=loyalty.admin.rewards.list;title=...]` |
| `loyalty.admin.basic-earn` | Admin — Basic Earn | `[asset:mockup;id=loyalty.admin.earn-basic.basic;title=...]` |
| `loyalty.admin.lifecycle-automation` | Admin — Lifecycle Automation | `[asset:mockup;id=loyalty.admin.lifecycle.list;title=...]` |
| `loyalty.admin.earn-studio` | Admin — Earn Studio | `[asset:mockup;id=loyalty.admin.earn-studio.advanced;title=...]` |
| `loyalty.admin.tier-settings` | Admin — Tier Settings | `[asset:mockup;id=loyalty.admin.tier.tiers;title=...]` |
| `loyalty.admin.personas` | Admin — Personas | `[asset:mockup;id=loyalty.admin.personas.personas;title=...]` |
| `loyalty.admin.missions` | Admin — Missions | `[asset:mockup;id=loyalty.admin.missions.list;title=...]` |
| `loyalty.admin.spin-wheel` | Admin — Spin Wheel | `[asset:mockup;id=loyalty.admin.spin-wheel.list;title=...]` |
| `loyalty.admin.survey` | Admin — Survey | `[asset:mockup;id=loyalty.admin.survey.list;title=...]` |
| `loyalty.admin.signup-form` | Admin — Signup Form | `[asset:mockup;id=loyalty.admin.signup-form.settings;title=...]` |
| `loyalty.perfectcustomerjourney1` | The perfect retention journey : Purchase -> Member | `[asset:mockup;id=loyalty.core.earn.marketplace;title=...]` · `[asset:mockup;id=loyalty.core.rewards.list;title=...]` · `[asset:mockup;id=loyalty.core.tier.benefit;title=...]` |
| `loyalty.perfectcustomerjourney2` | Member -> Engaged | `[asset:mockup;id=loyalty.campaign.your-brand-missions.cover;title=...]` |
| `loyalty.perfectcustomerjourney3` | AI: not just analyze, but act | `[asset:fixed_diagram;slide=loyalty.perfectcustomerjourney3]` |
| `loyalty.ai-journey-force` | Why AI? A journey doesn't move itself | `[asset:fixed_diagram;slide=loyalty.ai-journey-force]` |
| `loyalty.high-level-flow` | High-level overview | `[asset:fixed_diagram;slide=loyalty.high-level-flow]` |
| `loyalty.line-shopify-flow` | CONVERT - Brand.com & Shopify integration | `[asset:mockup;id=loyalty.core.earn.marketplace;title=...]` |
| `loyalty.basic.brand-com-earn` | EARN : Brand.com & Shopify | `[asset:mockup;id=loyalty.core.earn.marketplace;title=...]` |
| `loyalty.basic.shopify-loyalty-widget` | Shopify loyalty widget | `[asset:fixed_diagram;slide=loyalty.basic.shopify-loyalty-widget]` |
| `loyalty.diagram.earnburn` | Earn & burn (points flow) | `[asset:fixed_diagram;slide=loyalty.diagram.earnburn]` |
| `loyalty.raas.strategy-pillars` | Reward sourcing as a managed service | `[asset:fixed_diagram;slide=loyalty.raas.strategy-pillars]` |
| `loyalty.raas.sku-breadth` | Reward catalog breadth (>2,000 SKUs) | `[asset:fixed_diagram;slide=loyalty.raas.sku-breadth]` |
| `loyalty.raas.categories` | Reward sourcing strategy (illustration) | `[asset:fixed_diagram;slide=loyalty.raas.categories]` |
| `loyalty.raas.operation-flow` | Rewards operation flow | `[asset:fixed_diagram;slide=loyalty.raas.operation-flow]` |
| `amp.admin.ai-analysis-merchant` | AMP Admin — AI Analysis | `[asset:mockup;id=loyalty.admin.ai-analysis.list;title=...]` |
| `amp.admin.audience-builder` | AMP Admin — Audience Builder | `[asset:mockup;id=loyalty.admin.audience.list;title=...]` |
| `amp.admin.decisioning-agent` | AMP Admin — AI Decisioning Agent | `[asset:mockup;id=loyalty.admin.decisioning.list;title=...]` |
| `amp.admin.rules-builder` | AMP Admin — Journey Builder | `[asset:mockup;id=loyalty.admin.journey.list;title=...]` |
| `loyalty.core.coupon-claim` | Coupon — claim | `[asset:mockup;id=loyalty.core.coupon.collect;title=...]` · `[asset:mockup;id=loyalty.core.coupon.wallet;title=...]` · `[asset:mockup;id=loyalty.core.coupon.detail;title=...]` |
| `loyalty.core.coupon-redeem` | Coupon — redeem | `[asset:mockup;id=loyalty.core.coupon.use-at-retailer;title=...]` · `[asset:mockup;id=loyalty.core.coupon.retailer-confirm;title=...]` · `[asset:mockup;id=loyalty.core.coupon.used;title=...]` |
