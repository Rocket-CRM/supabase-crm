# Function Naming Conventions

This document defines the naming prefixes for database functions based on their use case and caller context.

## Prefix Categories

### `api_` - External API Contract

**Use case**: General-purpose operations exposed to external systems  
**Called by**: Third-party APIs, customer apps, admin UI (for simple operations)  
**Design characteristics**:
- Standard REST-like CRUD operations
- Stable versioned contract requiring backward compatibility
- Accepts external identifiers (external_user_id, sku_code, store_code)
- Resolves codes to internal UUIDs
- Simple request/response structures
- Graceful handling of missing references

**Examples**:
- `api_create_purchase()` - Create purchase transaction
- `api_get_user_balance()` - Retrieve currency balance
- `api_list_rewards()` - List available rewards
- `api_redeem_reward()` - Redeem reward with points

**Security**: SECURITY DEFINER, merchant_id from API key validation or context

---

### `api_*_cached` - External API with Redis Caching

**Use case**: High-read, low-write operations exposed to external systems with performance optimization  
**Called by**: Third-party APIs, customer apps, admin UI  
**Design characteristics**:
- Same as `api_` prefix but with automatic Redis caching
- 5-minute TTL per merchant by default
- Automatic cache invalidation on data change (trigger-based)
- All related enrichments in single response (joins, aggregations)
- Multi-language support returned in single call
- Transparent to caller - caching logic entirely backend-managed

**Naming pattern**: `api_{operation}_{data_type}_cached` or `api_{operation}_{data_type}_full_cached`
- `_cached` = basic caching with automatic invalidation
- `_full_cached` = caching + complete enriched data (translations, aggregations, stock stats)

**Examples**:
- `api_get_rewards_full_cached()` - All rewards with translations, stock, redemption counts
- `api_list_merchants_cached()` - Merchant catalog with metadata
- `api_get_catalog_full_cached()` - Complete product catalog with pricing and availability

**Backend Pattern**:
```
Check Redis → HIT → Return (2-5ms)
            → MISS → Query Database → Store in Redis (5 min TTL) → Return
Cache invalidation on INSERT/UPDATE of related tables via triggers
```

**Security**: SECURITY DEFINER, merchant_id from API key validation or context

**See also**: [Caching Design Methodology](./caching_methodology.md)

---

### `bff_` - Backend-for-Frontend Optimization

**Use case**: Complex operations designed specifically for frontend UI ease of use  
**Called by**: Admin UI only (WeWeb)  
**Design characteristics**:
- Request/response structures optimized for UI patterns
- Nested upsert operations handling parent + children atomically
- Update-by-ID pattern preserving existing IDs (never delete-and-recreate)
- Comprehensive operation counts in response (created/updated/deleted/skipped)
- Handles complex array updates in single call
- Individual parameters with `p_` prefix (not single JSONB object)

**Examples**:
- `bff_upsert_persona_group_with_personas()` - Update group with 25+ nested personas
- `bff_upsert_store_attribute_set_with_members()` - Update set with member array
- `bff_upsert_mission_with_conditions()` - Update mission with conditions and outcomes

**Security**: SECURITY DEFINER, uses get_current_merchant_id() from headers/JWT

**Key pattern**: Designed for admin configuration screens where complex nested data needs atomic updates with ID preservation for maintaining external references.

---

### `admin_` - Privileged Admin Operations

**Use case**: Sensitive admin-only actions requiring elevated privileges  
**Called by**: Admin UI only  
**Design characteristics**:
- Destructive or privileged operations
- System configuration changes
- Access control and security management
- Bulk operations affecting multiple records

**Examples**:
- `admin_generate_api_key()` - Generate API keys
- `admin_revoke_api_key()` - Deactivate API keys
- `admin_get_api_keys()` - List merchant's API keys
- `admin_bulk_delete_users()` - Bulk user deletion
- `admin_reset_system_state()` - System resets

**Security**: SECURITY DEFINER with admin role validation

---

### `fn_` - Internal Business Logic

**Use case**: Core system functions not exposed to users  
**Called by**: Triggers, other functions, system processes  
**Design characteristics**:
- Pure business logic implementation
- Optimized for performance
- Assumes validated input from caller
- May not have extensive validation
- Internal implementation details

**Examples**:
- `fn_evaluate_mission_conditions()` - Mission condition matching engine
- `fn_process_mission_outcomes()` - Reward distribution logic
- `fn_update_mission_progress()` - Progress state management
- `fn_evaluate_tier_status()` - Tier calculation engine

**Security**: SECURITY DEFINER or SECURITY INVOKER depending on needs

---

### `trigger_` - Database Event Handlers

**Use case**: Functions called by database triggers on data changes  
**Called by**: Database triggers (AFTER INSERT/UPDATE/DELETE)  
**Design characteristics**:
- Event detection and routing
- Queue message creation
- Immediate response (minimal processing)
- Delegates to processing functions

**Examples**:
- `trigger_tier_eval_on_purchase()` - Purchase completion → tier queue
- `trigger_process_purchase_currency()` - Purchase completion → currency queue
- `trigger_mission_evaluation_realtime()` - Event → mission evaluation

**Security**: SECURITY DEFINER

---

### `cron_` - Scheduled Job Functions

**Use case**: Batch processing and scheduled maintenance  
**Called by**: pg_cron or edge function schedulers  
**Design characteristics**:
- Batch operations processing multiple records
- Periodic evaluations
- Maintenance and cleanup tasks
- Smart scheduling with early exit logic

**Examples**:
- `cron_process_tier_queue()` - Process tier evaluation queue every 30 seconds
- `cron_expire_currency()` - Daily currency expiry processing
- `cron_send_reminders()` - Scheduled notification sending

**Security**: SECURITY DEFINER

---

### `util_` - Utility/Helper Functions

**Use case**: Reusable utilities shared across multiple systems  
**Called by**: Other functions  
**Design characteristics**:
- Pure functions (no side effects)
- Calculations, formatting, validation
- No database modifications
- Shared logic

**Examples**:
- `util_calculate_expiry_date()` - Date calculation
- `util_format_phone_number()` - Format standardization
- `util_validate_email()` - Input validation

**Security**: Usually SECURITY INVOKER

---

### No Prefix - User Self-Service RPC

**Use case**: End-user customer-facing operations  
**Called by**: Customer mobile apps, customer portals  
**Design characteristics**:
- User context from auth.uid()
- Self-service actions
- User data scoped to authenticated user
- Rate limiting considerations

**Examples**:
- `accept_mission()` - User accepts mission
- `claim_mission_outcomes()` - User claims rewards
- `process_checkin()` - User checks in
- `redeem_reward_with_points()` - User redeems from catalog

**Security**: SECURITY DEFINER with auth.uid() validation

---

## Quick Reference Matrix

| Prefix | Caller | Security Context | Design Pattern | Stability |
|--------|--------|------------------|----------------|-----------|
| `api_` | External APIs + FE | merchant_id (API key) | Simple CRUD, code resolution | High (versioned) |
| `api_*_cached` | External APIs + FE | merchant_id (API key) | Caching with invalidation | High (versioned) |
| `bff_` | Admin UI only | get_current_merchant_id() | Complex nested upsert | Medium (UI coupled) |
| `admin_` | Admin UI only | get_current_merchant_id() | Privileged operations | Medium |
| `fn_` | System internal | Passed explicitly | Business logic | Low (can refactor) |
| `trigger_` | Database events | From NEW/OLD | Event routing | Low |
| `cron_` | Schedulers | Query-driven | Batch processing | Low |
| `util_` | Other functions | Varies | Pure utilities | Low |
| None | End users | auth.uid() | Self-service | Medium |

---

## Key Distinction: api_ vs bff_

### api_ = General Reusable Operations
- Simple input → simple output
- Anyone can use (API, frontend, mobile)
- Example: `api_create_purchase(final_amount, items[])`

### bff_ = Frontend-Optimized Admin Workflows  
- Complex nested input → detailed operation counts output
- Admin UI only (configuration screens)
- Designed for specific UI patterns
- Example: `bff_upsert_mission_with_conditions(mission_id, conditions: [{id, ...update}, {...create}])`
  - Updates existing conditions by ID
  - Creates new conditions without ID
  - Deletes conditions not in array
  - Returns: {parent_created: bool, children_created: 2, children_updated: 3, children_deleted: 1}

**Both are frontend-facing**, but `bff_` specifically optimizes for **complex admin configuration workflows** that external APIs don't need, while `api_` serves **everyone** with simple reusable operations.

---

## Implementation Guidelines

### When creating new functions:

1. **Is it part of external API?** → Use `api_` prefix
2. **Is it complex nested admin UI pattern?** → Use `bff_` prefix  
3. **Is it privileged admin-only?** → Use `admin_` prefix
4. **Is it internal business logic?** → Use `fn_` prefix
5. **Is it a trigger handler?** → Use `trigger_` prefix
6. **Is it a scheduled job?** → Use `cron_` prefix
7. **Is it end-user self-service?** → No prefix

### Migration strategy:

**New functions**: Apply convention from day one  
**Existing functions**: Rename critical external-facing functions first, internal functions gradually  
**Breaking changes**: Maintain aliases during transition period for backward compatibility

