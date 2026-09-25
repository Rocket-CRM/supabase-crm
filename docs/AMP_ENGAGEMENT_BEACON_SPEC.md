# AMP Engagement Beacon — Member App Integration Spec

Contract for the Rocket Loyalty member app (`*.rocket-loyalty.app`) to report page-engagement
metrics for visits that originate from AMP workflow message links. Backend side is live:
`link-redirect` and `engagement-beacon` edge functions on project `wkevmsedchftztoolkmi`.

## How a tracked visit arrives

Links inside AMP messages (LINE / SMS) are wrapped as
`https://wkevmsedchftztoolkmi.supabase.co/functions/v1/link-redirect/<token>`.
The redirect logs the click and 302s to the original destination **with `rct=<token>`
appended to the query string**. A page load with an `rct` query param is a tracked visit.

## What the app must do

On every page load:

1. Read `rct` from the query string (workflow tracked link). If absent, read `bc` (broadcast id UUID). If neither is present, do nothing (zero overhead).
2. Generate a session id (e.g. `crypto.randomUUID()`), one per page load.
3. Report events to the beacon endpoint:

**Tracked link (`rct`):**

```
POST https://wkevmsedchftztoolkmi.supabase.co/functions/v1/engagement-beacon
Content-Type: application/json

{
  "token": "<rct value>",
  "session_id": "<uuid>",
  "events": [
    { "type": "page_view" },
    { "type": "page_time",    "value": 42.5 },   // seconds on page (number)
    { "type": "scroll_depth", "value": 85 }      // max scroll reached, percent 0-100
  ]
}
```

**Targeted broadcast (`bc`):** same `events` shape, but body uses `broadcast_id` (UUID from `bc` query param) and `Authorization: Bearer <member access token>` (loyalty session JWT). Only sent when the member is logged in.

Recommended timing:

- `page_view` — immediately on load (fire-and-forget `fetch`).
- `page_time` + `scroll_depth` — once, on `visibilitychange` → `hidden` (and `pagehide`),
  via `navigator.sendBeacon` so it survives tab close. Track `page_time` as accumulated
  visible time; track `scroll_depth` as the max percentage reached
  (`(scrollY + innerHeight) / document.body.scrollHeight * 100`).

Sending `page_time`/`scroll_depth` more than once per session is fine — the backend
aggregates with MAX per (token, session), so send cumulative values, not deltas.

## Endpoint behavior

- Public endpoint, no auth header needed; the token is the correlation key.
- CORS allows origins on `rocket-loyalty.app` (any subdomain) and `localhost`; requests
  without an Origin header (webview `sendBeacon`) are accepted.
- Responses: `200 {success:true, inserted:n}`, `400` invalid payload, `404` unknown token,
  `403` disallowed origin. All failures are safe to ignore client-side — never block UX.
- Limits: max 20 events per request; `page_time` capped at 86,400s; `scroll_depth` clamped 0–100.
- Event types accepted: `page_view`, `page_time`, `scroll_depth` (clicks are logged
  server-side by `link-redirect`).

## Do not

- Do not strip the `rct` param before other routing logic runs; stripping it from the
  visible URL afterwards (history.replaceState) is fine once captured.
- Do not send events when no `rct` is present.
- Do not retry failed beacon posts aggressively; one retry max.
