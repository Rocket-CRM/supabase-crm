# Sources index — KCG Corporation, CRM & Loyalty Program (kcg-202609)

Researcher: proposal-researcher · Brief: sources · Date: 2026-09-29

Conventions
- Clause IDs are the TOR's own (`tor.txt`). Bullets under a clause get a letter suffix in source order (`4.1.a` = first bullet under 4.1). Unnumbered sentences get `-P1`, `-P2` (paragraph order within the clause). Line numbers refer to `sources/tor.txt`.
- Thai quotes are verbatim and kept short; the gloss is ours.
- Kind: **F** functional · **NF** non-functional · **C** commercial · **S** submission / delivery / process · **OPT** optional service (bid separately; priced separately).
- Thai Buddhist years: 2569 = 2026, 2570 = 2027.

---

## 1. Documents

| File | What it is | Length |
|---|---|---|
| `sources/tor.txt` | KCG Corporation PCL Terms of Reference (Thai, English feature terms mixed in), text extracted from `tor.docx`. Title: "ข้อกำหนดขอบเขตงานจัดหาและให้บริการระบบ CRM & Loyalty Program". Clauses 1–28, then an unnumbered submission timetable, then 30 (no clause 29). | ~433 lines |
| `sources/brief.md` | **Not a customer document.** Rocket founder's internal brief (2026-09-29): scope, emphasis and positioning directives for the proposal. Indexed separately in §9. | ~60 lines |

Header facts (tor.txt L1–4): project "CRM & Loyalty Program"; coordinator Thanaporn Srimuang; target "B2C (Direct to Consumer)"; business "Food"; project period "พฤศจิกายน 2569 – มกราคม 2570" (Nov 2026 – Jan 2027); "กำหนด Go-live: 1 มกราคม 2570" (1 Jan 2027).

---

## 2. Requirements (TOR)

### 1 Objectives (L6–19) — context/goals, not scored items
| ID | Thai (verbatim, short) | Gloss | Kind |
|---|---|---|---|
| 1-P1 | "ออกแบบ จัดหา พัฒนา ติดตั้ง เชื่อมต่อระบบ และให้บริการบริหารจัดการ Loyalty Platform" | Design, supply, develop, install, integrate and operate a loyalty platform | F |
| 1-P1b | "สนับสนุนการทำ Customer Segmentation, Personalized Marketing และ Omnichannel Customer Experience" | Support segmentation, personalized marketing, omnichannel CX | F |
| 1-P2 | "รองรับการเก็บข้อมูลสมาชิกและ Transaction จากช่องทาง Offline และ Online" | Capture members and transactions from offline and online | F |
| 1.1 | "จัดทำฐานข้อมูลลูกค้าและ First-party Customer Data" | Build a customer database / first-party data | F |
| 1.2 | "สร้างและบริหาร Loyalty Program ภายใต้แบรนด์ KCG" | Loyalty programme under the KCG brand | F |
| 1.3 | "เพิ่ม Customer Engagement, Customer Retention และ Customer Loyalty" | Raise engagement, retention, loyalty | F |
| 1.4 | "เพิ่มความถี่ในการซื้อและ Customer Lifetime Value" | Raise purchase frequency and CLV | F |
| 1.5 | "รองรับการสะสมคะแนน การแลกคะแนน Coupon และ Privilege ต่าง ๆ" | Earn, redeem, coupons, privileges | F |
| 1.6 | "รองรับ Customer Segmentation และ Personalized Campaign" | Segmentation and personalized campaigns | F |
| 1.7 | "รองรับการทำ CRM Campaign และ Mission ทั้งแบบ Basic และ Advanced" | CRM campaigns and missions, basic and advanced | F |
| 1.8 | "เชื่อมต่อข้อมูลจากช่องทาง Offline และ Online เข้าสู่ระบบ Loyalty Platform กลาง" | Connect offline + online data into one central platform | F |
| 1.9 | "วิเคราะห์ Customer Behavior และ Customer Journey" | Analyse behaviour and journey for marketing planning | F |
| 1.10 | "รองรับการขยายระบบและช่องทางการใช้งานในอนาคต" | Extensible to future systems/channels | NF |

### 2 Bidder qualifications (L21–29)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 2.1 | "นิติบุคคลที่จดทะเบียนถูกต้องตามกฎหมายในประเทศไทย" | Thai-registered legal entity in software/CRM/loyalty | S |
| 2.2 | "สามารถแสดง Customer Reference ที่มีลักษณะงานใกล้เคียง" | Show similar customer references | S |
| 2.3 | "มีบุคลากร … ตั้งแต่การออกแบบระบบ การ Integration การ Implement การทดสอบระบบ และการให้บริการหลังการ Go-live" | Adequate staff across design→post-go-live | S |
| 2.4 | "เชื่อมต่อระบบกับระบบภายนอกผ่าน API หรือ Integration Method ที่เหมาะสม" | Can integrate with external systems via API etc. | NF |
| 2.5 | "มาตรฐานด้าน Information Security … (PDPA)" | InfoSec standard, Thai PDPA compliance | NF |
| 2.6 | "เปิดเผยข้อมูล Certificate … เช่น ISO 27001 หรือมาตรฐานอื่นที่เทียบเท่า" | Disclose ISO 27001 or equivalent | S |
| 2.7 | "เปิดเผยข้อมูลอย่างครบถ้วน หากมีกรณีที่อาจก่อให้เกิดผลประโยชน์ทับซ้อน" | Disclose conflicts of interest | S |
| 2.8 | "ให้บริการและสนับสนุนระบบตลอดระยะเวลาของสัญญา … ตาม SLA" | Support/maintenance for contract term per SLA | NF |

### 3 Scope & responsibilities (L31–41)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 3.1 | "จัดหาและ Implement ระบบ CRM & Loyalty Platform … ตั้งค่าระบบ ทดสอบระบบ และเตรียมความพร้อมก่อน Go-live" | Supply, implement, configure, test, prepare go-live | S |
| 3.2 | "รองรับสมาชิกได้ไม่น้อยกว่า 200,000 Members" | ≥200,000 members, scalable | NF |
| 3.3 | "ไม่น้อยกว่า 100,000 Orders ต่อเดือน" | ≥100,000 orders/month across all channels, scalable | NF |
| 3.4 | "Touchpoint … • LINE Official Account / ทั้งนี้ Website / Shopify จะเป็น Future Integration" | Only touchpoint now: LINE OA; Website/Shopify future | F |

### 4 CRM & Loyalty scope (L43–81)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 4.1.a | "Member Registration" | Registration | F |
| 4.1.b | "Member Login ด้วย Mobile Phone Number" | Login by mobile number | F |
| 4.1.c | "Member Profile" | Profile | F |
| 4.1.d | "Member Status" | Status | F |
| 4.1.e | "Member Activity" | Activity | F |
| 4.1.f | "Member Transaction History" | Transaction history | F |
| 4.1.g | "Point Balance" | Point balance | F |
| 4.1.h | "Coupon / Reward History" | Coupon/reward history | F |
| 4.1.i | "Member Consent" | Consent | F |
| 4.1.j | "Member Communication Preference" | Communication preferences | F |
| 4.1-P1 | "เชื่อมต่อกับ LINE Official Account และสามารถ Sync ข้อมูลสมาชิกกับ LINE Current KCG" | Connect LINE OA and sync members with KCG's current LINE | F |
| 4.2-P1 | "Loyalty Program ภายใต้ 1 Brand คือ KCG / ชื่อ Loyalty Program: KCG Rewards" | One brand, programme named "KCG Rewards" | F |
| 4.2-P2 | "รองรับ Point Currency เดียว" | Single point currency, configurable earn/burn rules | F |
| 4.2.a | "Point Earning" | Earn | F |
| 4.2.b | "Point Redemption" | Redeem | F |
| 4.2.c | "Point Adjustment" | Manual adjustment | F |
| 4.2.d | "Bonus Point" | Bonus points | F |
| 4.2.e | "Extra Point" | Extra points | F |
| 4.2.f | "Point Expiration" | Expiry | F |
| 4.2.g | "Point Reversal" | Reversal | F |
| 4.2.h | "Point Transaction History" | Point ledger history | F |
| 4.2-P3 | "อัตราการแลกยอดซื้อเป็นคะแนนจะถูกกำหนดโดยบริษัทฯ และระบบต้องสามารถปรับเปลี่ยนเงื่อนไข" | Spend-to-point rate set by KCG, must be changeable | F |
| 4.3-P1 | "แบ่งสมาชิกเป็น Tier และสามารถกำหนดเงื่อนไขของแต่ละ Tier" | Tiers with configurable criteria | F |
| 4.3.a–e | "Spending / Purchase Frequency / Transaction / Customer Behavior / Campaign Participation" | Example tier criteria (listed "เช่น" = e.g.) | F |
| 4.3-P2 | "กำหนดสิทธิประโยชน์และ Campaign ที่แตกต่างกันในแต่ละ Tier" | Different benefits and campaigns per tier | F |
| 4.3-P3 | "จำนวน Tier และเงื่อนไข … กำหนดร่วมกัน … ในช่วง Implementation" | Tier count/criteria co-defined during implementation | S |

### 5 Campaign Management (L83–100)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 5-P1 | "สร้างและบริหาร Campaign ได้ด้วยตนเอง โดยไม่จำเป็นต้องพัฒนาระบบใหม่ทุกครั้ง" | Self-serve campaigns, no dev per campaign | F |
| 5.1.1 | "Automated Welcome Coupon" | Automatic welcome coupon | F |
| 5.1.2 | "Automated Up-Tier Coupon" | Automatic coupon on tier upgrade | F |
| 5.1.3 | "Automated Birth Month Coupon" | Automatic birth-month coupon | F |
| 5.1.4 | "Point Redemption Campaign" | Point-redemption campaign | F |
| 5.1.5 | "Privilege Campaign" | Privilege campaign | F |
| 5.1-P1 | "กำหนด Target Audience, ระยะเวลา, เงื่อนไข, สิทธิประโยชน์ และจำนวนสิทธิ์" | Campaign: audience, period, conditions, benefit, quota | F |
| 5.2.1 | "Mission – Spending / … แสดงเฉพาะสมาชิกบาง Tier หรือบาง Segment" | Spending mission; visible only to some tiers/segments | F |
| 5.2.2 | "Mission – Friend Get Friend / … ไม่จำกัดจำนวน Campaign ภายใต้ขีดความสามารถของระบบ" | Referral mission; unlimited campaigns within system capacity | F |
| 5.2.3 | "Mission – Survey / สร้าง Survey และกำหนดเงื่อนไขหรือ Reward" | Create surveys, reward completion | F |

### 6 Reward & Privilege (L102–108)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 6.1 | "E-Coupon" | E-coupon | F |
| 6.2 | "Extra Points from Mission" | Extra points as a mission reward | F |
| 6.3 | "Lucky Draw" | Lucky draw | F |
| 6.4 | "Merchandise" | Physical merchandise | F |
| 6-P1 | "กำหนดเงื่อนไขการได้รับสิทธิ์ วันเริ่มต้น วันสิ้นสุด จำนวนสิทธิ์ และ Target Audience" | Eligibility, start/end, quota, audience per reward | F |

### 7 Transaction Capturing (L110–124)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 7-P1 | "รับข้อมูล Transaction จากช่องทางต่าง ๆ" | Receive transactions from channels below | F |
| 7.1 | "Flagship Store – POS" | Offline: flagship store POS | F |
| 7.2 | "Modern Trade" | Offline: modern trade (no system named) | F |
| 7.3 | "Event – POS" | Offline: event POS | F |
| 7.4 | "Website / Brand.com" | Online: brand website | F |
| 7.5 | "Shopee จำนวน 2 Accounts" | Online: Shopee ×2 accounts | F |
| 7.6 | "Lazada จำนวน 2 Accounts" | Online: Lazada ×2 accounts | F |
| 7.7 | "TikTok Shop จำนวน 2 Accounts" | Online: TikTok Shop ×2 accounts | F |
| 7.8 | "LINE Official Account" | Online: LINE OA | F |
| 7.9 | "MAKRO PRO" | Online: Makro PRO | F |
| 7.10 | "Future Channel / Shopify" | Future: Shopify | F |
| 7-P2 | "ระบุวิธีการเชื่อมต่อของแต่ละ Channel เช่น API, Webhook, File Transfer … พร้อมระบุข้อจำกัดและค่าใช้จ่ายเพิ่มเติม" | Per channel: state method, limits, extra cost | S/C |

### 8 System Integration (L126–135)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 8.1 | "POS" | POS (vendor unnamed) | F |
| 8.2 | "ERP – SAP" | SAP ERP | F |
| 8.3 | "Marketplace" | Marketplaces | F |
| 8.4 | "LINE Official Account" | LINE OA | F |
| 8.5 | "MAKRO PRO" | Makro PRO | F |
| 8.6 | "Shopify – Future Integration" | Shopify (future) | F |
| 8-P1 | "จัดทำ Integration Architecture และ Data Flow" | Provide integration architecture + data flow | S |

### 9 Reporting & Dashboard (L137–166)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 9.1-P1 | "Standard Report ไม่น้อยกว่า 10 Reports" | ≥10 standard reports | F |
| 9.1.a–j | "Member Report / New Member / Active Member / Transaction / Sales / Point Earn / Point Burn / Point Balance / Campaign Performance / Reward / Coupon Redemption" | Example reports (10 listed, "ตัวอย่าง") | F |
| 9.2.a–h | "Member Growth / Active Member / Sales / Transaction / Average Spending / Point Earn / Burn / Campaign Performance / Redemption Rate" | Dashboard KPIs (listed "เช่น") | F |
| 9.3 | "ส่งต่อหรือเชื่อมโยงข้อมูลไปยัง Data Lake ของบริษัทฯ ได้ตาม Data Architecture ที่บริษัทฯ กำหนด" | Feed KCG's data lake per KCG's architecture (mandatory; priced as own line in 21) | F |
| 9.4 | "Agentic AI – Optional … เสนอเป็น Optional Service และแสดงค่าใช้จ่ายแยกต่างหาก" | Optional agentic AI for CRM/loyalty, priced separately | OPT |

### 10–13 Optional services (L167–215) — see §7
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 10.1 | "Campaign Setup" | BPO: campaign setup | OPT |
| 10.2 | "Survey Setup" | BPO: survey setup | OPT |
| 10.3 | "Report Management" | BPO: report management | OPT |
| 10.4 | "Update New SKU" | BPO: new SKU updates | OPT |
| 10.5 | "Manage / Operate Loyalty Platform" | BPO: operate platform | OPT |
| 10.6 | "Upload และ Setup E-Coupon Code" | BPO: upload/set up coupon codes | OPT |
| 10.7 | "Setup และ Edit Campaign" | BPO: set up / edit campaigns | OPT |
| 10-P1 | "ไม่รวม Copywriting และ Digital Asset Development" | Excludes copywriting and digital assets unless agreed | OPT |
| 11.1 | "Check and Approve Receipt" | Receipt approval: check/approve | OPT |
| 11.2 | "Build Transaction Record" | Build transaction record | OPT |
| 11.3 | "Build Point Record" | Build point record | OPT |
| 11.4 | "Upload Transaction Record เข้าสู่ระบบ" | Upload transactions into system | OPT |
| 11-P1 | "ระบุค่าบริการและ SLA" | State fee and SLA for receipt service | C |
| 12.1.a–e | "North-star Metrics / Member Health Scorecard / Weekly / Monthly / Quarterly Reporting / Monthly Executive Presentation / Quarterly Strategy Refresh" | Consultation: loyalty metrics monitoring | OPT |
| 12.2.a–j | "Customer & Segmentation Strategy / Tier Strategy / Transactional Segmentation / Behavioral Segmentation / Mission & Campaign Planning / Always-on Campaign Calendar / Mission Design / Surprise & Delight Campaign / Partner Offers / Seasonal Campaign" | Consultation: action recommendations | OPT |
| 12-P1 | "เสนอค่าบริการแยกจากค่า Platform และค่า Implementation" | Price separately from platform and implementation | C |
| 13.a–g | "ร้านอาหาร / เครื่องดื่ม / Fuel / Shopping / Lifestyle / Entertainment / Other Privileges" | Partner privilege sourcing categories | OPT |
| 13-P1 | "Monthly Fee, Annual Fee, Commission หรือค่าใช้จ่ายอื่น ๆ" | State fee model | C |

### 14 Data Security & PDPA (L217–231)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 14.1–14.10 | "PDPA Compliance / Data Encryption / Access Control / User Permission / Audit Log / Backup & Recovery / Disaster Recovery / Data Retention / Data Deletion / Incident Management" | Ten security controls (each a separate item) | NF |
| 14-P1 | "แสดง Certificate … เช่น ISO 27001, ISO 29110 … พร้อมระบุขอบเขตของ Certificate" | Show certificates and their scope | S |

### 15 SLA (L233–244)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 15.1–15.10 | "System Availability / Uptime / Planned Maintenance / Critical Incident / High Severity Incident / Medium Severity Incident / Response Time / Resolution Time / System Recovery Time / Backup / Disaster Recovery" | SLA items to specify | NF |
| 15-P1 | "ระบุ RTO … และ RPO … อย่างชัดเจน" | State RTO and RPO explicitly | NF |

### 16 Implementation & PM (L246–260)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 16.1–16.11 | "Requirement Gathering / Solution Design / System Configuration / Integration / Data Mapping / Development / Customization (ถ้ามี) / System Integration Test / UAT / User Training / Go-live / Hypercare / Post Go-live Support" | Project plan phases | S |
| 16-P1 | "จัด Project Manager และทีมงานที่มีความเหมาะสม" | Dedicated PM and team | S |

### 17 Timeline (L262–276)
| ID | Thai / table | Gloss | Kind |
|---|---|---|---|
| 17-T | "Procurement / Supplier Selection Aug – Oct 2026; Project Kick-off Nov 2026; Implementation / Configuration Nov – Dec 2026; Integration & UAT Dec 2026; Go-live 1 Jan 2027" | Indicative timeline | S |
| 17-P1 | "จัดทำ Detailed Project Timeline และ Milestone" | Provide detailed timeline + milestones | S |

### 18 Users & volumes (L278–283)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 18.1 | "สมาชิก จำนวน 200,000 Members" | 200k members | NF |
| 18.2 | "Transaction จำนวน 100,000 Orders / Month" | 100k orders/month | NF |
| 18.3 | "รองรับการเพิ่มจำนวนสมาชิกและ Transaction ในอนาคต" | Growth headroom | NF |
| 18-P1 | "ระบุข้อจำกัดของระบบ เช่น Maximum Members, Transaction Volume, API Call, Storage และ Concurrent Users" | Declare system limits | S |

### 19 Deliverables (L285–299)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 19.1–19.13 | "System / Platform ที่พร้อมใช้งาน / System Configuration / Integration ตาม Scope / System Architecture / Data Flow / Integration Flow / User Manual / Admin Manual / Technical Document / API Document / Test Scenario / Test Result / UAT Sign-off / Training / Post Go-live Support" | 13 deliverables | S |

### 20 Warranty & after-sales (L301–303)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 20-P1 | "ระบุระยะเวลารับประกันระบบและบริการหลังการ Go-live" | State warranty period | C |
| 20-P2 | "System Defect … แก้ไขโดยไม่คิดค่าใช้จ่ายเพิ่มเติม" | Fix own defects free under SLA | C |

### 21 Pricing (L305–373)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 21-T | Table rows 1–10: "Loyalty Platform License / Implementation / Setup / Integration / API / BPO – Platform Management / Receipt Approval / Loyalty Consultation / Privilege Acquisition / Data Lake / Agentic AI – Optional / Other Services" × columns "Monthly Fee / Yearly Fee / One-time Fee" | Required price grid | C |
| 21-P1 | "License Fee / Implementation Fee / Maintenance Fee / API / Integration Fee / Transaction Fee / Member Fee / Storage Fee / Support Fee / Additional User Fee / Additional Transaction Fee / ค่าใช้จ่ายอื่น ๆ" | Disclose all fee types | C |
| 21-P2 | "ระบุรายการ Included / Excluded อย่างชัดเจน" | Explicit included/excluded list | C |

### 22–28 Contract terms (L375–421)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| 22 | "หลักประกันการปฏิบัติตามสัญญาในอัตราร้อยละ 5" | 5% performance bond | C |
| 23 | "กระบวนการ Change Request … เสนอรายละเอียดผลกระทบและค่าใช้จ่าย" | KCG may change scope via CR; bidder states cost/time impact | C |
| 24 | "คัดเลือกเฉพาะผู้เสนอราคาที่สามารถปฏิบัติตาม … ได้ครบถ้วน" | Only fully compliant bids considered; incomplete may be rejected; decision final | S |
| 25.1–25.17 | "Company Profile / หนังสือรับรองบริษัท / … Customer Reference / Solution Proposal / System Architecture / Integration Architecture / Project Plan / Team Structure / SLA / Data Security / PDPA Compliance / Certificate / Commercial Proposal / … Included / Excluded / Optional Services / Service Level และ Support Model / … ข้อจำกัดของระบบ / Demo / System Presentation" | 17 submission documents | S |
| 25-P1 | "ลงนามโดยผู้มีอำนาจลงนาม … และประทับตราบริษัท" | All documents signed by authorised signatory + stamp | S |
| 26 | "ยืนราคาไม่น้อยกว่า 60 (หกสิบ) วัน" | Price valid ≥60 days from submission | C |
| 27 | "ชำระเงินภายหลังจากผู้เสนอราคาได้ส่งมอบงานประจำงวด … ตรวจรับงาน" | Payment per milestone after acceptance | C |
| 28 | "ประเมินผลการดำเนินงาน … คุณภาพของระบบ ความครบถ้วนของ Function การ Integration ความสามารถในการรองรับปริมาณข้อมูล การให้บริการ และการปฏิบัติตาม SLA" | Performance evaluated in implementation + post go-live on these dimensions | S |

### Unnumbered submission timetable (L422–428) and 30 Contact (L431–434)
| ID | Thai | Gloss | Kind |
|---|---|---|---|
| SUB-1 | "ส่ง TOR 17 สิงหาคม 2569 / รับ Brief รูปแบบ Online, On Site 18-28 สิงหาคม 2569" | TOR issued 17 Aug 2026; briefing 18–28 Aug | S |
| SUB-2 | "ยื่นซองใบเสนอราคา … ในวันที่ 30 กันยายน 2569 เท่านั้น จ่าหน้าและยื่นเอกสารถึง คุณธนาภรณ์ ศรีเมือง (จัดซื้อ)" | Sealed bid delivered 30 Sep 2026 only, to Procurement, KCG HQ, 3059 Sukhumvit, Bangchak, Phra Khanong | S |
| SUB-3 | "ประกาศผู้ที่ได้รับคัดเลือก 31 ตุลาคม 2569" | Award announced 31 Oct 2026 | S |
| 30 | "thanaporn.s@kcgcorporation.com ฝ่าย General Procurement / Indirect Material (Facility)" | Contact; further detail per RFQ documents | S |

**Counts (items as indexed, expanding grouped rows):** Functional ≈ 95 · Non-functional ≈ 33 · Submission/process ≈ 60 · Commercial ≈ 12 · Optional-service items ≈ 40 (9.4, 10.x, 11.x, 12.x, 13.x). Core product-facing functional clauses (sections 3.4–9.3): 77 line items.

---

## 3. Their structure

- Flat numbered sections 1–28, then an unnumbered timetable block, then 30. **No clause 29.**
- Section headings verbatim: 1 วัตถุประสงค์ · 2 คุณสมบัติของผู้มีสิทธิเสนอราคา · 3 ขอบเขตหน้าที่และความรับผิดชอบของผู้เสนอราคา · 4 ขอบเขตระบบ CRM & Loyalty Program (4.1 Member Management, 4.2 Loyalty Program, 4.3 Member Tier) · 5 Campaign Management (5.1 Basic Campaign, 5.2 Advanced Campaign) · 6 Reward & Privilege · 7 Transaction Capturing (sub-heads Offline Channel / Online Channel / Future Channel) · 8 System Integration · 9 Reporting & Dashboard (9.1 Standard Report, 9.2 Dashboard, 9.3 Data Lake, 9.4 Agentic AI – Optional) · 10 BPO / Platform Management – Optional · 11 Receipt Approval – Optional · 12 Loyalty Consultation – Optional · 13 Privilege Acquisition – Optional · 14 Data Security & Personal Data Protection · 15 Service Level Agreement (SLA) · 16 Implementation & Project Management · 17 Project Timeline · 18 จำนวนผู้ใช้งานและปริมาณข้อมูล · 19 การส่งมอบงาน · 20 การรับประกันและบริการหลังการขาย · 21 ราคาและค่าใช้จ่าย · 22 หลักประกันการปฏิบัติตามสัญญา · 23 เงื่อนไขการเปลี่ยนแปลงขอบเขตงาน · 24 สิทธิในการพิจารณาข้อเสนอ · 25 การเสนอราคา · 26 กำหนดยืนราคา · 27 การชำระเงินค่าบริการ · 28 ระยะเวลาการดำเนินโครงการ · 30 ติดต่อเพื่อขอข้อมูลเพิ่มเติม.
- Blocks: functional 3–9 · optional services 9.4, 10–13 · NFR 14, 15, 18 · delivery 16, 17, 19, 20 · commercial/process 21–28.
- **Mixed levels.** 4.x uses bullets; 5 goes to three levels (5.1.1); 6/7/8/14/15/16/19 are flat numbered lists of nouns with no description; 9.1/9.2/12 use bullets marked "ตัวอย่าง"/"เช่น" (examples, not exhaustive). Most items are single nouns ("Point Reversal", "Merchandise") — little stated behaviour.
- Duplicated scope across sections: volumes (3.2/3.3 = 18.1/18.2); channels (3.4, 7, 8 overlap and differ); certificates (2.6, 14-P1); SLA/DR (14.6–14.7, 15.9–15.10); timeline (header, 17, 28).
- Mirrors a Rocket-friendly flow: Member → Points → Tier → Campaign → Reward → Earn channels → Integration → Reporting.

---

## 4. Vocabulary (their terms)

| Term | Where | Note |
|---|---|---|
| KCG Rewards | 4.2 | Programme name. Single brand "KCG". |
| Point Currency เดียว | 4.2 | One point currency. |
| Bonus Point / Extra Point | 4.2.d/e | Two separate bullets, undefined — see ambiguities. |
| Extra Points from Mission | 6.2 | Reward type; suggests "Extra Point" = points given as a reward. |
| Touchpoint vs Channel | 3.4 vs 7 | Touchpoint = member-facing surface (LINE OA); Channel = where transactions happen. Terms not defined. |
| LINE Current KCG | 4.1-P1 | Implies an existing KCG LINE OA (and possibly existing members) to sync with. |
| Member Status | 4.1.d | Undefined (active/blocked? tier?). |
| Privilege / Privilege Campaign | 1.5, 5.1.5, 6 | Benefits beyond coupons; also partner privileges (13). |
| Mission (Spending / Friend Get Friend / Survey) | 5.2 | "Advanced Campaign" = missions. |
| Basic vs Advanced Campaign | 5, 1.7 | Automated coupons + redemption/privilege = Basic; missions = Advanced. |
| Up-Tier Coupon, Birth Month Coupon | 5.1 | Automated triggers. |
| E-Coupon, Lucky Draw, Merchandise | 6 | Reward types. |
| Flagship Store, Modern Trade, Event | 7.1–7.3 | Offline channels. Modern Trade = retailer chains (not KCG-owned POS). |
| Website / Brand.com | 7.4 | Brand D2C site. |
| MAKRO PRO | 7.9, 8.5 | Makro's online marketplace/wholesale platform. |
| Data Lake | 9.3, 21 #8 | KCG-owned; architecture set by KCG. |
| Agentic AI | 9.4 | Optional, under Reporting section. |
| BPO / Platform Management | 10 | Outsourced operation of the platform. |
| Receipt Approval | 11 | Manual receipt verification service → transaction + point records. |
| Loyalty Matrix Monitoring | 12.1 | Likely "metrics". Includes North-star Metrics, Member Health Scorecard. |
| Surprise & Delight, Always-on Campaign Calendar, Partner Offers | 12.2 | Consultation vocabulary. |
| Privilege Acquisition | 13 | Sourcing partner privileges (F&B, fuel, lifestyle…). |
| Orders vs Transaction | 3.3, 18.2 | Volume stated as "Orders"; used interchangeably with Transaction. |

---

## 5. Pains and goals (verbatim)

The TOR states no explicit pains; goals are in §1. Quotable lines:
- "สร้างและบริหารฐานข้อมูลลูกค้า เพิ่ม Customer Engagement และ Customer Loyalty" — 1-P1 (L7)
- "เพื่อจัดทำฐานข้อมูลลูกค้าและ First-party Customer Data ของบริษัทฯ" — 1.1 (L10)
- "เพื่อเพิ่มความถี่ในการซื้อและ Customer Lifetime Value" — 1.4
- "เพื่อเชื่อมต่อข้อมูลจากช่องทาง Offline และ Online เข้าสู่ระบบ Loyalty Platform กลาง" — 1.8
- "เพื่อให้บริษัทฯ สามารถวิเคราะห์ Customer Behavior และ Customer Journey เพื่อนำไปใช้ในการวางแผนทางการตลาด" — 1.9
- "เพื่อรองรับการขยายระบบและช่องทางการใช้งานในอนาคต" — 1.10
- "สร้างและบริหาร Campaign ได้ด้วยตนเอง โดยไม่จำเป็นต้องพัฒนาระบบใหม่ทุกครั้งที่ต้องการสร้าง Campaign" — 5-P1 (L84) — implies past pain of dev-dependent campaigns.
- "ให้ข้อมูลลูกค้าและข้อมูลการซื้อสามารถนำมาใช้ในการบริหาร Loyalty Program ได้อย่างมีประสิทธิภาพ" — 1-P2 (L8)

Implied situation (our inference, flag as such): heavy sales through marketplaces (3 platforms × 2 accounts), Makro PRO and modern trade where KCG does not own the customer relationship → first-party data is the core goal; D2C on LINE OA today, website/Shopify coming.

---

## 6. Boundaries and constraints

- **Customer:** KCG Corporation PCL, Food, B2C/D2C. One brand (KCG), one programme (KCG Rewards), one point currency.
- **Touchpoint (member-facing) now:** LINE Official Account only (3.4). Future: Website / Shopify (3.4, 7.10, 8.6).
- **Transaction channels (7):** Offline — Flagship Store POS, Modern Trade, Event POS. Online — Website/Brand.com, Shopee ×2, Lazada ×2, TikTok Shop ×2, LINE OA, MAKRO PRO. Future — Shopify. Bidder must state method (API/Webhook/File Transfer/other), limits and extra cost per channel (7-P2).
- **Systems to integrate (8):** POS (vendor unnamed), SAP ERP, Marketplace, LINE OA, MAKRO PRO, Shopify (future). KCG Data Lake (9.3) per KCG's architecture.
- **Data ownership:** KCG sets point conversion rate (4.2-P3); data lake architecture is KCG's (9.3); tier design co-defined (4.3-P3). No statement on data residency/hosting.
- **Volumes:** ≥200,000 members; ≥100,000 orders/month; growth headroom (3.2, 3.3, 18). Must declare limits: max members, transaction volume, API calls, storage, concurrent users (18-P1).
- **Security:** PDPA; ISO 27001 / ISO 29110 or equivalent with certificate scope (2.6, 14-P1); 10 controls (14.1–14.10); RTO/RPO (15-P1).
- **Languages:** not specified. TOR in Thai; founder brief says write proposal in English first.
- **Hosting:** not specified.
- **Dates:** TOR issued 17 Aug 2026 · briefing 18–28 Aug 2026 · **submission 30 Sep 2026 only, hard-copy sealed envelope to KCG Procurement** · award 31 Oct 2026 · kick-off Nov 2026 · implementation Nov–Dec 2026 · integration & UAT Dec 2026 · **go-live 1 Jan 2027** (≈8 weeks from award to go-live, spanning year-end holidays).
- **Commercial:** 10-row price grid with Monthly/Yearly/One-time columns (21-T); full fee disclosure incl. transaction/member/storage/additional-user fees; Included/Excluded list; 5% performance bond; 60-day price validity; milestone payment after acceptance; change-request process.
- **Evaluation criteria:** none weighted. Only: full compliance required, incomplete bids may be rejected, decision final (24); performance evaluated on system quality, functional completeness, integration, volume capacity, service, SLA compliance (28). Demo/presentation as KCG specifies (25.17).
- **Submission documents:** 25.1–25.17, all signed by authorised signatory and company-stamped.
- **Contract term:** not stated (2.8 says "ตลอดระยะเวลาของสัญญา"); warranty period to be proposed by bidder (20).

---

## 7. Optional services (bid separately, price separately)

| Clause | Service | Scope items | Pricing ask |
|---|---|---|---|
| 9.4 | Agentic AI | "Solution ด้าน Agentic AI เพื่อสนับสนุน CRM และ Loyalty Management" (no further scope) | Separate cost; row 9 of 21-T |
| 10 | BPO / Platform Management | 10.1–10.7 (campaign setup, survey setup, report management, new SKU, operate platform, upload coupon codes, set up/edit campaigns); excludes copywriting and digital assets | Row 4 of 21-T |
| 11 | Receipt Approval | 11.1–11.4 (check/approve receipt, build transaction & point records, upload) | Fee + SLA required (11-P1); row 5 |
| 12 | Loyalty Consultation | 12.1 monitoring (5 items), 12.2 recommendations (10 items) | Separate from platform & implementation (12-P1); row 6 |
| 13 | Privilege Acquisition | Partner privileges: restaurants, beverages, fuel, shopping, lifestyle, entertainment, other | Monthly/annual/commission model (13-P1); row 7 |

Note: 21-T also lists "Data Lake" (row 8) as a priced line though 9.3 is mandatory, and "Other Services" (row 10).

---

## 8. Ambiguities (for the parent / a human)

**See first**
1. **Touchpoint vs channel scope for Website.** 3.4 lists only LINE OA as touchpoint, "Website / Shopify จะเป็น Future Integration"; but 7.4 lists "Website / Brand.com" as a current Online Channel for transaction capture, and 7.10/8.6 list Shopify as future. Is Brand.com a Shopify store (then 7.4 = future), or a separate site needing capture at go-live?
2. **Shopify plugin vs TOR.** Founder brief makes the Shopify plugin a headline ("Convert – shopify"); TOR treats Shopify only as future integration (3.4, 7.10, 8.6). Need framing: included now as a ready capability vs. priced as future phase.
3. **Marketing automation / AI decisioning have no mandatory clause.** Brief makes rule-based MA and AI decisioning central; TOR only implies it (1-P1b "Personalized Marketing", 1.6, 5.1 "Automated … Coupon") and puts AI under 9.4 "Agentic AI – Optional" inside Reporting. No outbound messaging channel (LINE push, SMS, email) is named anywhere. Parent must decide whether MA sits in core scope/price or under 9.4.
4. **"Modern Trade" (7.2)** — offline channel with no stated system or data source. Retailer POS data is not KCG's; likely receipt upload, which links to Optional 11 Receipt Approval. Unclear if receipt-scan earning is expected in core.
5. **"2 Accounts" per marketplace (7.5–7.7)** — two shops each on Shopee/Lazada/TikTok Shop. Unstated whether these are different brands/sub-brands, official vs. secondary stores, or regions; affects connector count and pricing (7-P2 asks for per-channel cost).
6. **"Bonus Point" vs "Extra Point" (4.2.d/e)** — listed separately, undefined. 6.2 "Extra Points from Mission" hints Extra = points as a mission/campaign reward, Bonus = multiplier/promotional earn on purchase — unconfirmed.
7. **Mission – Survey (5.2.3) vs Survey Setup (10.2)** — survey building is a core feature, and survey setup is also an optional BPO task. Likely core = capability, BPO = someone operating it; confirm no double counting.

**Also**
8. **Mission – Spending (5.2.1)** description only says it can be shown to some tiers/segments — no spend mechanic (threshold, period, stamp) stated.
9. **"LINE Current KCG" sync (4.1-P1)** — implies an existing LINE OA with existing friends/members; migration of an existing member base is not mentioned (16.5 is only "Data Mapping").
10. **Member login by phone (4.1.b)** — OTP inside LINE? Required also outside LINE (future website)?
11. **ERP – SAP (8.2)** — direction and purpose unstated (product/SKU master? sales? point liability postings?). Possibly tied to 10.4 "Update New SKU".
12. **POS (7.1, 7.3, 8.1)** — vendor unnamed; unclear if flagship and event POS are the same system.
13. **MAKRO PRO (7.9)** — Makro PRO is largely a B2B/wholesale buyer platform; fits awkwardly with "B2C (Direct to Consumer)" and with member identification. How are buyers matched to members?
14. **Data Lake (9.3)** — mandatory, yet priced as its own row (21-T #8); KCG's data architecture not described (push vs. pull, format, frequency).
15. **Standard reports (9.1)** — "ไม่น้อยกว่า 10" with exactly 10 examples; are the examples the required set?
16. **Tier criteria "Customer Behavior" / "Campaign Participation" (4.3)** — non-spend tier qualification; undefined.
17. **Referral "unlimited campaigns" (5.2.2)** — "ไม่จำกัดจำนวน Campaign ภายใต้ขีดความสามารถของระบบ" — commercial implication vs. campaign-unit pricing.
18. **Volumes** — "100,000 Orders ต่อเดือน" across all channels; no peak/concurrency figure, but 18-P1 asks us to state concurrent users.
19. **Contract term & warranty** — not stated; bidder proposes (20). Affects monthly vs. yearly vs. one-time columns.
20. **No clause 29**; timetable block unnumbered — possibly a lost heading in extraction or source.
21. **Submission logistics** — "ยื่นซองใบเสนอราคา … 30 กันยายน 2569 เท่านั้น" implies physical sealed delivery on a single day, signed and stamped (25-P1). Today is 29 Sep 2026.
22. **Buyer is Procurement / Indirect Material (Facility)** — business owner (marketing/CRM) unnamed; evaluation criteria unweighted.
23. **Language of proposal** not specified; TOR is Thai.

---

## 9. Internal brief — emphasis directives (Rocket founder, `sources/brief.md`)

Not customer requirements. Wording quoted verbatim; IDs are ours (`B-nn`) with line numbers.

| ID | Line | Directive (verbatim, short) | Topic |
|---|---|---|---|
| B-01 | L4 | "Includes loyalty, core loyalty campaigns, marketing automation (both rule-based and AI decisioning), and also the Shopify plugin." | Scope of offer |
| B-02 | L8 | "Let's do it in English first. Using the proposal workflow" | Language / process |
| B-03 | L10 | "study the requirement MDs carefully, especially the concept and journey part, technical parts not so much, but only where relevant." | Research depth |
| B-04 | L12 | "Leave out the technical parts for now." | Exclusion |
| B-05 | L14 | "use Mermaid diagrams, but be restricted to only sequence diagrams or node diagrams." | Diagram style |
| B-06 | L17–18 | "Earn — must cover all channels they request. Highlight omni-channel. Highlight that we support first-party, third-party, online, and offline … be clear on this abstraction and concept" | Earn section |
| B-07 | L21 | "Be clear first on the role of marketing automation as activation. And why activation matters" | Activate section |
| B-08 | L22–23 | "we have two types: 1. Rule-based deterministic workflows: marketer sets conditions, sends actions, and AI decisioning" | MA types |
| B-09 | L24–28 | "Give an example first … including advanced stuff like: delay; condition split after delay; split in sending. Condition split can be both loyalty activities and interaction." | MA example |
| B-10 | L29 | "rule-based workflows … face the issue of optimizing for the mean and assuming fixed journeys … an expert marketer or relationship manager for every single individual customer at scale … AI decisioning, it is the answer." | AI decisioning argument |
| B-11 | L31–32 | "AI not only analysis but decisioning … admin can ask a question of our AI on the portal or install our MCP and ask in their own AI environment (for example, Claude or ChatGPT). The AI will have access to the data that that admin has access to" | AI analysis |
| B-12 | L34 | "our AI is not only analysis but action … Not just increase convenience, but actually increase outcomes." | AI positioning |
| B-13 | L34–40 | "the perfect journey: 1. Join 2. Earn 3. Burn 4. Grow 5. Engage and return 6. Convert to second purchase on first-party platform" | Journey frame |
| B-14 | L41 | "Customers rarely move along this journey. Quote the Newtons quote in the slides." | Narrative device |
| B-15 | L41 | "activation … is not only a good-to-have but is an underlying fabric that connects each journey part together" | Core thesis |
| B-16 | L41 | "seen over a 50% increase in member engagement and conversion to next purchase on our estimate" | Claim (founder estimate — attribute carefully) |
| B-17 | L43–46 | "AI appears in two parts: 1. AI for analysis … dashboard and analytics part. 2. AI decisioning … activations part. We also need a summary section on just AI to combine these two" | AI placement + summary section |
| B-18 | L48–49 | "Convert – shopify … display the table: the difference between normal Shopify integration, which is usually just user and member sync and shopify plugin for which we are the only Thailand company that is a plugin" | Shopify section + comparison table |
| B-19 | L51–53 | "section that mentions why rocket is different / end to end: b2c crm - both loyaty, mini cdp, marketing automation, ai, ecommerce plugin. from 3rd party acquisition to 1st party conversion" | Why Rocket — end-to-end |
| B-20 | L54 | "thailand's only shopoify loyalty plugin - how its different from orders" | Why Rocket — Shopify |
| B-21 | L55 | "ai that can act not just analyze - connecting layer" | Why Rocket — AI |
| B-22 | L56 | "stack of the future - event driven, workflow orchestration- guaranteed resilience. able to accept high national level concurrency at significiantly lower cost" | Why Rocket — stack (note tension with B-04) |
| B-23 | L57 | "service - dedidicated 2 CS slas strategist, free graphic etc. whatever to make project success as we depend on renewal" | Why Rocket — service |
| B-24 | L58–59 | "conusmer surplus strategy … with AI, the cost of producing software has become significantly lower. We intend to pass this cost savings on to the customer … our pricing for the same level of features is significantly lower … ensure that it never makes sense for our enterprise customers to develop the solution themselves" | Why Rocket — pricing philosophy |

Brief ↔ TOR tensions to note: B-01/B-18 Shopify plugin vs TOR "Future Integration"; B-01/B-08 MA + AI decisioning vs TOR 9.4 "Optional"; B-04 "leave out technical parts" vs TOR submission items 25.5/25.6/25.10/25.16 and 8-P1 (architecture, data flow, security, limits are required submission documents); B-23 "free graphic" vs TOR 10-P1 excluding digital assets from BPO (a differentiator opportunity).
