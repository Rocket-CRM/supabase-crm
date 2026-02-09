# Version 55: Persona Injection & Conditional Groups Fix

**Date:** February 6, 2026  
**Status:** ✅ Ready to deploy

## Issue

Even with `selected_persona_id` correctly set, `persona_groups` was still being returned in `missing_data`, unlike default/custom fields which correctly filtered out fields with values.

## Root Cause

The `filterToMissingOnly` function always included the full `persona` structure in `missing_data`, regardless of whether the user had already selected a persona. This differed from how default/custom fields were handled (only included if missing).

## Changes

### 1. Persona ID Injection (Lines 332-335)

```typescript
// ✅ FIX: Inject user's persona_id into template if they have one
if (profileTemplate && userPersonaId && profileTemplate.persona) {
  profileTemplate.persona.selected_persona_id = userPersonaId;
}
```

**Why needed**: Even with `auth_user_id` fixed, the RPC function may not always return the correct `selected_persona_id` due to caching or JWT context issues. Since `bff-auth-complete` already has the user's `persona_id`, we inject it directly.

### 2. Conditional Persona Groups (Lines 71-77)

```typescript
const missingData: any = {
  persona: template.persona ? {
    ...template.persona,
    persona_groups: (!template.persona.selected_persona_id) ? template.persona.persona_groups : []
  } : null,
  pdpa: [],
  default_fields_config: [],
  custom_fields_config: []
};
```

**Why needed**: Matches the pattern used for default/custom fields - only include `persona_groups` if the user hasn't selected a persona yet (`selected_persona_id` is null).

## Expected Behavior After Fix

**For user with persona (`+66966564526`):**
```json
{
  "missing_data": {
    "persona": {
      "selected_persona_id": "5f1aa0fb-3e2b-4c60-9bd4-5f7e8a5374cd",
      "persona_groups": [],  // ✅ Empty because persona already selected
      "merchant_config": { ... }
    },
    "default_fields_config": [],  // Empty because all default fields filled
    "custom_fields_config": [...]  // Only groups with missing required custom fields
  }
}
```

**For user without persona:**
```json
{
  "missing_data": {
    "persona": {
      "selected_persona_id": null,
      "persona_groups": [...]  // ✅ Included because persona not yet selected
    }
  }
}
```

## Files Modified

1. `/Users/rangwan/Documents/Supabase CRM/supabase/functions/bff-auth-complete/index.ts` - Updated function
2. `/Users/rangwan/Documents/Supabase CRM/backups/bff-auth-complete/VERSION_55_PERSONA_INJECTION.ts` - Backup
3. `/Users/rangwan/Documents/Supabase CRM/backups/bff-auth-complete/VERSION_55_README.md` - Documentation

## Deployment

The updated function code is ready at:
`/Users/rangwan/Documents/Supabase CRM/supabase/functions/bff-auth-complete/index.ts`

Deploy via Supabase dashboard or CLI to apply changes.
