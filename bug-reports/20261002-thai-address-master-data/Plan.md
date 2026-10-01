# Thai address master data — missing, corrupt and bogus rows (Group 3: DEF-034/035/036/037/038)

## Summary
The address dropdowns on `/store` checkout and the member address book are correct; the data under them is not. The shared Thai address tables are missing 85 subdistricts and one district, carry 13 corrupt names and 13 invented codes, and have wrong English names. This affects every merchant. The fix is one data migration on the three shared tables, plus re-pointing 63 saved member addresses that use the invented codes. No app code changes.

**Decision:** ship Phase 1 now (everything that our own data proves wrong). Hold Phase 2 (the 95 rows where our name or postcode disagrees with the reference) until each row is checked against DOPA, because the QA reference is a community dataset.

## Status (2 Oct 2026)
- **Phase 1 applied** as migration `fix_thai_address_master_phase1`. Every check in `verify.sql` passes; the subdistrict total is 7,437. Backups are in `_bak_20261002_*`.
- Changes against the plan, all found while reviewing the generated SQL:
  - **3 inserts held** (`410116` ต.นาข่า, `500108` ต.สุเทพ, `830104` ต.รัษฎา). Each name already exists under a neighbouring live code (`410111`, `500109`, `830105`), so inserting would show it twice. One corrupt-name fix is held for the same reason: `110401` → ต.ตลาด duplicates `110402`.
  - **4 English-fill rows held** (`380103`, `410111`, `500109`, `830105`). Our Thai name there is a neighbour's name, so the reference English name would contradict it.
  - **4 district English names kept**, because the reference is wrong or disagrees with our Thai name: `3801` (reference says "Mueang Bueng Kan", our Thai name is อ.บึงกาฬ), `6008` ท่าตะโก (reference says "Takhli"), `6011` ลาดยาว (reference says "Phayuha Khiri"), `7107` ทองผาภูมิ (reference says "Pha Phum").
  - **62 addresses re-pointed, not 63.** The one address on district `4026` is the same address as the `402615` one.
- Decisions: Phase 1 approved to apply. Phase 2 is decided by DOPA / Thailand Post; apply only where they agree.
- **Phase 2 applied** as migration `fix_thai_address_master_phase2` (generator `scripts/gen_phase2.py`, checks `verify_phase2.sql`, all passing). Backups are in `_bak_20261002_p2_*`.
  - Sources (in `./data`): DOPA `ccaatt.xlsx` (directory as of 1 Sep 2023; DOPA blocks non-Thai IPs, so it came from the Wayback Machine snapshot of 7 Aug 2026), and Thailand Post's nationwide postcode poster (2018, `file.thailandpost.com/upload/content/_5e856abf6c77a.pdf`).
  - Subdistrict codes now equal DOPA's 7,436 active codes exactly (count + md5 asserted inside the migration). Inserted `410116`, `500108`, `830104`; deleted `200409`, `920221`, `920222`, `920414`.
  - 67 subdistrict names corrected to DOPA (DOPA agreed with the reference on every one). Kept our name where DOPA agrees with us: `600113` ต.วัดไทรย์, `840902` ต.พะแสง.
  - Code swaps went wider than the 4 held: names were swapped or rotated in `1104`, `1411`, `4101`, `4618`, `4812`, `5001`, `8301`. 19 saved addresses were moved to the code that officially holds the name the member saw. Postcodes back this up: the Suthep addresses carry 50200 (Suthep), not 50100 (Mae Hia). `380103`, `430111` and `441106` held names DOPA doesn't list anywhere; no saved addresses, plain renames.
  - Districts: `3801` → อ.เมืองบึงกาฬ / Mueang Bueng Kan (the reference was right); `4906`, `9310`, `9508` spelling. `6008`, `6011`, `7107` stay as they are (DOPA agrees with us).
  - Postcodes: 4 changed where Thailand Post gives one code for the whole tambon and it matches the reference (`240409` 24130, `551502` 55130, `901604` 90115, `920106` 92000). Of the other 23, Thailand Post agrees with us on 10; the other 13 split by village, so no single postcode is right and we kept ours.
  - Not changed: `501805` (DOPA 2023 says ต.แม่หลอง; we and the reference say ต.สบโขง) and `502202` (DOPA ทุ่งปี๊ vs ทุ่งปี้). Either needs a Royal Gazette check before changing.

## Evidence
- QA diff vs `kongvut/thai-province-data` @ `7d689e4`: [`./data/DrPong_address_data_issues.csv`](./data/DrPong_address_data_issues.csv)
- Live checks on `wkevmsedchftztoolkmi` (2 Oct 2026):
  - Bangkok has 154 subdistricts (reference 180). เขตจตุจักร (`1030`) has only `103001` แขวงลาดยาว; `103002`–`103006` are absent.
  - Corrupt names: `150612` `ต.ม่ว��เตี้ย`, `550610` `ต.ต.ผาทอง`, `920903` `ต.ต.หนองบัว`, `520101` (note + `*` in name), `200409` `ต.เขตการปกคองพิเศษพัทยา`.
  - 13 codes that are not in the reference; 10 have `zip_code = 0`, 2 have `NULL`.
  - All 9 Phayao districts are named `Mueang Phayao` in English; province `11` is `Samut Prakarn`; 271 subdistricts have `subdistrict_name_en = '0'` (not in the QA list, same class of defect).
  - District `4029` อ.เวียงเก่า does not exist. Its 3 subdistricts sit under an invented district `4026` with invented codes and zip 0.

## What's going wrong
The dropdown loaders (`loyalty-user/src/lib/address/th-admin.ts`, `loadThaiSubdistricts` etc.) read `address_th_province` / `address_th_district` / `address_th_subdistrict` by parent id with no filter or row cap. Missing rows are simply not in the tables. The tables were loaded before migrations were tracked (no seed SQL anywhere), and have never been refreshed.

## Likely cause
A one-off, incomplete import of Thai admin data, with hand edits on top (municipality names, notes, invented codes). Not a UI or query bug.

## What the fix must respect
- **Tables are global** (no `merchant_id`, public `SELECT`). Text PK `id` (2/4/6-digit TIS code); child FK columns `province_id` / `district_id` are bigint, no FK constraints. Child rows carry denormalised parent names (`province_name_*`, `district_name_*`) that must be filled on insert.
- **Names keep the Thai prefix convention**, since the UI shows names verbatim: provinces `จ.` (except กรุงเทพมหานคร), districts `อ.` / Bangkok `เขต`, subdistricts `ต.` / Bangkok `แขวง`. The reference has no prefixes; add them when generating SQL.
- **Saved addresses store the code and a text copy of the name.** `user_address` keeps `province_code` / `district_code` / `subdistrict_code` and text mirrors `city` / `district` / `subdistrict`. The Shopify checkout receives names resolved at checkout time. Redemption delivery snapshots are historical; leave them alone.
- **Inserting rows is safe for old short codes.** The alphabetical-position fallback in `canonicalizeThaiSubdistrictId` (`th-admin.ts:179`) does not match stored data: 0 rows use it, and only 17 short-code rows sit in the 58 districts that receive inserts (all in `1009`). Server functions resolve by id, `sort_order` or name only.
- **`ต.จ.ป.ร.` (`850406`, Ranong) is a real tambon name, not a doubled prefix.** QA listed it under DEF-035; leave it as is (7 saved addresses use it).

## Proposed fix

| Phase | Touches | Does not touch | Risk |
|---|---|---|---|
| 1 — provable from our data (DEF-034, 035, 037 with a target, 038, 4026→4029, EN `'0'`) | 3 master tables; 63 `user_address` rows | App code; redemption snapshots; DEF-036 rows | Low. One transaction; remap happens before delete |
| 2 — needs official check (DEF-036: 64 name, 25 postcode, 2 name+postcode, 4 district-name diffs; 4 codes with no target) | Same tables, updates only | Anything DOPA does not confirm | Medium if applied without verification |

## Execution steps

### Phase 1 — one migration, `fix_thai_address_master_phase1` (parent applies via Supabase MCP)

The executor generates the SQL with a script from the reference JSON at `kongvut/thai-province-data@7d689e4` (`api/latest`), keyed by the CSV row codes. No hand-typed rows. The parent reviews the SQL, then applies it. Everything goes in one transaction, in this order:

1. **Insert district `4029`** อ.เวียงเก่า (province `40`, EN from reference, `sort_order` next in province 40).
2. **Insert the 85 missing subdistricts** (CSV `result = ไม่มีในเว็บ`), including `402901`–`402903`: `id`, prefixed `subdistrict_name_th`, `subdistrict_name_en`, `district_id`, denormalised district/province names, `zip_code` from the reference.
3. **Re-point saved addresses**, updating each code and its text mirror together:

   | From | To | `user_address` rows |
   |---|---|---:|
   | `104701` | `104702` แขวงบางนาเหนือ | 6 |
   | `105001` | `105002` แขวงบางบอนเหนือ | 3 |
   | `110105` | `110116` ต.ท้ายบ้านใหม่ | 4 |
   | `402615` | `402902` ต.เมืองเก่าพัฒนา (district → `4029`) | 1 |
   | `402602` / `402608` | `402901` / `402903` (district → `4029`) | 0 |
   | `440828` | `440817` ต.หนองบัว | 0 |
   | `490501` | `490503` ต.บ้านซ่ง | 0 |
   | `530306` | `530407` ต.ท่าแฝก, **and `district_code` `5303` → `5304`** อ.น้ำปาด | 48 |
   | district `4026` | `4029` | 1 |

   Before updating, write the old values of every touched row (id plus the old code/text columns) to the migration's `RAISE NOTICE` output or a dated backup table. That is the rollback path.
4. **Delete** the 9 remapped invented subdistricts and district `4026`, after asserting that zero `user_address` rows still reference them (abort the transaction if any do).
5. **Fix corrupt names** on the same `id`: `150612`, `550610`, `920903`, `520101`, and the 6 municipality-named rows, from the reference with the prefix re-added. Exclude `850406` ต.จ.ป.ร. and `200409` (Phase 2).
6. **Fix English names**: the 37 district EN names (CSV `ชื่ออังกฤษไม่ตรง`), province `11` → `Samut Prakan`, and the 271 subdistricts with `subdistrict_name_en = '0'`. Refresh the denormalised EN parent names on child rows.

**How we'll know it worked** (SQL after apply):
- Bangkok has 180 subdistricts; `district_id = 1030` returns 5 แขวง.
- No subdistrict name contains `�` or starts with `ต.ต.`; no `zip_code` is 0 or NULL outside Phase 2's 4 held codes; no `subdistrict_name_en = '0'`.
- Phayao districts have 9 distinct EN names.
- `user_address` has zero rows on any deleted code.
- Render check: `/store` checkout → กรุงเทพมหานคร → เขตจตุจักร lists จอมพล / จันทรเกษม / ลาดยาว / เสนานิคม / จตุจักร, and the postcode fills 10900.

**Closeout:** add one changelog line in `supabase-crm` (`06-product-doc-closeout`). No requirement doc changes behaviour.

### Phase 2 — after verification (separate migration)
1. Check these against DOPA's official code list (stat.bora.dopa.go.th) and Thailand Post: the 91 subdistrict name/postcode diffs, the 4 district-name diffs, the 4 codes with no target (`200409` Pattaya special zone; `920221`, `920222`, `920414` in Trang), and the code-swap rows held from Phase 1 (`410111`/`410116`, `500108`/`500109`, `830104`/`830105`, `110401`/`110402`, `380103`). For each code-swap row, if DOPA confirms the reference code, re-point the saved addresses on the old code before renaming or inserting.
2. Apply only the rows where DOPA agrees with the reference. Delete `200409` and any Trang code DOPA doesn't list, provided none is referenced by a saved address (0 today).
3. Same "how we'll know" checks, scoped to the changed rows.

## Surfaces / owners
- Data: Supabase `wkevmsedchftztoolkmi`, tables `address_th_province`, `address_th_district`, `address_th_subdistrict`, `user_address`.
- Readers (no change needed): `loyalty-user/src/lib/address/th-admin.ts` (store checkout, address book, signup forms); `loyalty-admin` C360 and `src/lib/api/address.ts`; SQL `fn_get_user_address_snapshot`, `fn_resolve_th_address_codes`, `fn_thai_admin_*_id`.

## Open questions
- None. Both phases are live.

## Out of scope
- Form behaviour (postcode filtering, field order, "Bangkok" in TH mode): Group 2.
- About 762k legacy `user_address` rows store 1–4 digit codes (often the province `sort_order` in `district_code`). That is a separate legacy-import cleanup; this fix leaves those rows alone.
- Removing the alphabetical-position fallback in `th-admin.ts`. Nothing uses it, but deleting it is a code change outside this data fix.
- Table `thailand_province_district_subdistrict` is empty and nothing references it. It can be dropped in a separate cleanup.
- Drop the `_bak_20261002_*` and `_bak_20261002_p2_*` tables after a week or so without complaints.
- Checkout postcode for tambons that Thailand Post splits by village (e.g. ต.ท่าหลวง, ต.ทุ่งคอก, ต.ท่าม่วง): one postcode per subdistrict can't be right for every member. Whether the field stays editable is a Group 2 form question.
