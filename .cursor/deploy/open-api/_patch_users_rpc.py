#!/usr/bin/env python3
import re
from pathlib import Path

p = Path(__file__).with_name("api-users") / "index.ts"
text = p.read_text()
m = re.search(
    r"const \{ data, error \} = await crmClient\.rpc\('api_create_or_update_user', \{.*?\n      \}\);",
    text,
    re.S,
)
if not m:
    raise SystemExit("rpc block not found")

new = """const { data, error } = await crmClient.rpc('api_create_or_update_user', {
        p_merchant_id: merchantId,
        p_tel: body.tel,
        p_timezone: body.timezone ?? 'Asia/Bangkok',
        p_external_user_id: body.external_user_id ?? null,
        p_firstname: body.firstname ?? null,
        p_lastname: body.lastname ?? null,
        p_email: body.email ?? null,
        p_line_id: body.line_id ?? null,
        p_id_card: body.id_card ?? null,
        p_birth_date: body.birth_date ?? null,
        p_user_type: body.user_type ?? 'buyer',
        p_user_stage: body.user_stage ?? null,
        p_channel_email: body.channel_email ?? true,
        p_channel_sms: body.channel_sms ?? false,
        p_channel_line: body.channel_line ?? true,
        p_channel_push: body.channel_push ?? true,
        p_upsert: body.upsert ?? false,
        p_addresses: body.addresses ?? null,
        p_address_mode: body.address_mode ?? 'replace',
        p_form_submissions: body.form_submissions ?? null,
        p_acquisition_source: body.acquisition_source ?? null
      });"""

p.write_text(text[: m.start()] + new + text[m.end() :])
print("patched", p)
