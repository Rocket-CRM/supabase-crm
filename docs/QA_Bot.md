# QA Bot

How the QA bot tests Rocket CRM fixes as a real merchant admin and member. `qa_task_fetch` returns the `Surface:` sections for the apps a bug touches, plus `Procedure` and `Report format`. Edit headings only together with the CRM Knowledge MCP server, which looks them up by name.

All testing happens on the **New CRM** merchant (`newcrm`) in production. Other merchants on the same apps are live clients.

Credentials never go in this doc, in chat, or in a report. Logins live in the bot computer's signed-in sessions. When a session is gone, hand control to a human to sign in.

## Surface: admin

- **URL:** https://portal.rocket-loyalty.com
- **Account:** `qa-bot@newcrm.com`, role `admin` on New CRM only.
- **Login:** email and password. If the login page appears and the session is gone, hand control to a human.
- **Check first:** the merchant shown in the admin header is **New CRM**. If any other merchant is shown or selectable, stop and report BLOCKED.

### Creating data here

Merchant configuration is created through the admin screens: rewards, campaigns, missions, tiers, content, forms, members. For where a setting lives and what its fields mean, read the feature's requirements doc (`expected_rules` in the task, or `search_docs`).

## Surface: member

- **URL:** https://newcrm.rocket-loyalty.app
- **Account:** the QA test member, already signed in on the bot computer.
- **Login:** phone OTP or LINE. The bot can't receive OTPs. If a login, OTP, or LINE consent screen appears, hand control to a human. Never sign up with a phone number or LINE account of your own choosing.

### Creating data here

Member-side data comes from doing what a member does: completing the profile, earning, redeeming, joining missions, uploading receipts. Points the test needs up front come from the Open API (`Procedure`).

## Surface: shopify_admin

- **URL:** https://admin.shopify.com/store/33ub80-hz/apps/rocket-loyalty-crm (the Rocket Loyalty CRM app inside Shopify admin, store `33ub80-hz`)
- **Account:** the Shopify staff account signed in on the bot computer.
- **Login:** Shopify login and 2FA. Hand control to a human.
- **Check first:** the merchant the app shows is **New CRM**. If it shows another merchant, stop and report BLOCKED.
- Never change store settings, apps, themes, staff, or billing outside the Rocket Loyalty CRM app.

## Surface: storefront

- **URL:** https://33ub80-hz.myshopify.com/
- **Account:** the QA test customer, signed in through Shopify customer accounts.
- **Login:** if a storefront password page or a customer login code appears, hand control to a human.
- Never pay with a real card. If checkout needs a real payment to continue, stop and report BLOCKED.

## Procedure

1. `qa_tasks_list` and take the oldest bug.
2. `qa_task_fetch` for it. If it returns blocked, submit BLOCKED with that reason and move on.
3. Read the bug, the handoff, and `expected_rules`. `expected` in the handoff is the pass/fail rule. `expected_rules` explains the product rule behind it. `related` is background only, never a reason to fail.
4. Create everything in `setup`. Check that everything in `seeded` exists. If something can't be created or is missing, report BLOCKED and name it.
5. Do the `steps` as a user would: click, type, navigate. No dev tools or direct API calls unless a step says so.
6. Check every `expected` line. Then try one or two nearby variations a real user would plausibly hit: an empty field, going back, a refresh, a second attempt.
7. Screenshot the key step and the result.
8. `qa_result_submit`.

### Test data rules

- Name everything you create `QA-BOT <yyyy-mm-dd> <what it is>`, and list it in `created_records`.
- Never edit, deactivate, or delete a record you did not create.
- Never send a broadcast, message, notification, or campaign to anyone except the QA test member. If a test needs a real send to others, report BLOCKED.

### Open API

For data the screens can't create on demand, such as a purchase from a store or points to start with. Contract detail is in `requirements/Open_API.md`.

- **Base URL:** `https://open-api.rocket-loyalty.com/functions/v1`
- **Auth:** header `x-api-key` with the New CRM QA key kept in the bot environment. It is never written in requests you report.
- **Purchases:** `POST /api-purchases`
- **Points earn/burn:** `POST /api-wallet/transactions` with `dedup_key` starting `qa-bot:`
- **Members:** `POST /api-users`, for the QA test member only.

### When to stop

Stop and report BLOCKED instead of working around it when:

- a login, OTP, 2FA, or password page appears
- any merchant other than New CRM is shown
- a real payment or a real send to other people is needed
- `expected` and `expected_rules` don't say what the user should see
- the app is down or errors before the steps can run (put the error in `actual`)

## Report format

Submit one `qa_result_submit` per bug.

- `verdict`: `pass` when every `expected` line was observed. `fail` when any `expected` line was not observed. `blocked` when the test couldn't run as written.
- `did`: the steps actually taken, one line each.
- `expected_source`: the handoff's `expected` lines, plus the `expected_rules` heading they rest on, if any.
- `actual`: what happened. For a fail, name the `expected` line that wasn't met and what showed instead.
- `blocked_reason`: one sentence on what is missing, phrased as the question a human must answer. Null unless blocked.
- `created_records`: every `QA-BOT` record created.
- `side_issues`: anything else broken that was noticed, kept out of the verdict.
- `profile_version`: the version line from your profile.
- `screenshots`: PNGs of the key step and the result.
