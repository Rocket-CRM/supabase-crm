# Reward Redemption System - Complete Business & Technical Documentation

## Executive Summary

The Reward Redemption System is a sophisticated loyalty platform that orchestrates the complete lifecycle of reward management - from creation through redemption to fulfillment. Built on a **two-layer architecture** (eligibility layer determining WHO can redeem, and points pricing layer determining HOW MANY points required), the system supports dynamic points-based pricing that adapts to customer attributes (tier, type, persona, tags), multiple fulfillment methods (digital, physical, pickup, printed), and comprehensive stock/promo code management.

The system's distinguishing features include:
- **Multi-dimensional points matching engine** that evaluates four customer dimensions simultaneously for optimal pricing
- **Intelligent promo code management** supporting bulk imports with partner attribution and real-time availability tracking
- **Flexible fulfillment architecture** accommodating digital, physical, and hybrid reward delivery methods

## Table of Contents
- [Core Concepts & Glossary](#core-concepts--glossary)
- [Business Requirements](#business-requirements)
- [System Architecture](#system-architecture)
- [Database Schema](#database-schema)
- [Dynamic Points Calculation Engine](#dynamic-points-calculation-engine)
- [Reward Redemption Processing](#reward-redemption-processing)
- [Eligibility & Validation System](#eligibility--validation-system)
- [Promo Code Management](#promo-code-management)
- [Fulfillment & Delivery Management](#fulfillment--delivery-management)
- [Business Rules](#business-rules)
- [API Integration](#api-integration)
- [Implementation Examples](#implementation-examples)
- [System Operations & Monitoring](#system-operations--monitoring)


---

## Core Concepts & Glossary

### Reward Architecture Components

**Reward Master**: Central entity defining a redeemable benefit with all its properties, rules, and constraints. Each reward operates independently with its own eligibility criteria and pricing rules.

**Two-Layer System**: Architectural separation of concerns:
1. **Eligibility Layer**: Binary qualification check (WHO can see/redeem)
2. **Points Pricing Layer**: Dynamic cost calculation (HOW MANY points required)

**Multi-Dimensional Matching**: System evaluates four customer attributes simultaneously:
- **Tier**: Loyalty level (Bronze, Silver, Gold, Platinum, Diamond)
- **User Type**: Transactional role (buyer, seller)
- **Persona**: Business profile (Student, Corporate, SME)
- **Tags**: Behavioral markers (VIP, Early Adopter, Frequent Buyer)

### Reward Properties

**Visibility Types**:
- `user`: Public catalog - visible to all eligible end users
- `admin`: Administrative rewards - only visible in admin interfaces
- `campaign`: Campaign-specific - distributed through targeted campaigns

**Fulfillment Methods**:
- `digital`: Electronic delivery (codes, vouchers, downloads)
- `shipping`: Physical delivery requiring address
- `pickup`: Collection at designated store location
- `printed`: Self-print vouchers/certificates

**Online Store** (`online_store[]`): Free-text array of marketplace/storefront identifiers where the reward should be displayed (e.g. `shopify`, `bigcommerce`, `lazada`). NULL or empty means no marketplace distribution. No enum — values are merchant-defined.

**Expiration Modes**:
- `relative_days`: Expires X days after redemption
- `relative_mins`: Flash rewards expiring in minutes
- `absolute_date`: Fixed expiration for all redemptions

### Redemption States

**Redeemed Status** (`redeemed_status = true`): Points deducted, reward claimed by user

**Used Status** (`used_status = true`): Reward actually consumed (voucher used at store, product collected)

**Fulfillment Status**:
- `pending`: Awaiting processing
- `shipped`: Dispatched to customer
- `delivered`: Delivery confirmed
- `completed`: Fully fulfilled and closed
- `cancelled`: Redemption cancelled (points refunded)
- `reject`: Redemption rejected (failed validation)

### Points Calculation Concepts

**Specificity**: Number of dimensions specified in a condition (1-4)

**Match Score**: Number of dimensions that actually match user attributes

**Priority**: Tiebreaker when multiple conditions have same specificity

**Customer-Favorable Rule**: When all else equal, lowest points requirement wins

**Fallback Points**: Default cost when no conditions match (optional)

### Eligibility Dimensions

**Allowed Tier** (`allowed_tier[]`): Array of tier IDs permitted to redeem

**Allowed Type** (`allowed_type[]`): User types (buyer/seller) allowed

**Allowed Persona** (`allowed_persona[]`): Persona IDs permitted

**Allowed Tags** (`allowed_tags[]`): Required tag IDs (user must have at least one)

**Allowed Birth Month** (`allowed_birthmonth[]`): Month numbers (1-12) for birthday rewards

### Redemption Limits

**Scope Types**:
- `user`: Limit applies per individual user
- `total`: Global limit across all users

**Time Units**: `day`, `week`, `month`, `year` for frequency control

**Window Enforcement**: Optional date ranges for limit application

---

## Business Requirements

### Functional Requirements

#### 1. Reward Lifecycle Management
- **Creation**: Merchants define rewards with complete configuration
- **Activation**: Time-window based availability control  
- **Modification**: Update properties while maintaining redemption history
- **Deactivation**: Soft-delete preserving audit trail

#### 2. Multi-Dimensional Points Pricing
The system's core innovation - dynamic pricing based on customer attributes:

**Dimension-Based Pricing**:
- Different points for different customer segments
- Automatic best-price selection for customers
- Configurable fallback for unmatched users
- Optional free redemption support

**Matching Algorithm**:
1. Evaluate all active conditions for reward
2. Score by specificity (more dimensions = higher priority)
3. Apply priority weighting for business rules
4. Select lowest points at same specificity level

#### 3. Comprehensive Eligibility Control
**Mandatory Checks**:
- Tier qualification (if specified)
- User type compatibility
- Persona requirements
- Tag prerequisites
- Time window validation

**Optional Filters**:
- Birthday month restriction
- Stock availability
- Promo code pool status

#### 4. Redemption Limit Management
**User Limits**: Control individual redemption frequency
- Daily/weekly/monthly/yearly caps
- Lifetime maximum redemptions
- Window-specific restrictions

**Global Limits**: System-wide redemption control
- Total redemption cap
- Time-based global limits
- Campaign-specific quotas

#### 5. Inventory & Code Management
**Stock Control**: Optional inventory tracking
- Real-time availability checks
- Atomic stock deduction
- Oversell prevention

**Promo Code Assignment**:
- Pre-loaded unique code pools
- Automatic assignment on redemption
- Default codes for unlimited use
- One code per redemption transaction

#### 6. Multi-Channel Fulfillment
**Digital Fulfillment**:
- Immediate code delivery
- Email/SMS distribution
- In-app display

**Physical Fulfillment**:
- Address validation
- Shipping status tracking
- Delivery confirmation

### Non-Functional Requirements

#### Performance Requirements
- **Redemption Processing**: < 3 seconds end-to-end
- **Eligibility Check**: < 500ms for multi-dimensional evaluation
- **Points Calculation**: < 200ms with condition matching
- **Concurrent Handling**: Support 1000+ simultaneous redemptions

#### Reliability Requirements
- **Transaction Atomicity**: All-or-nothing redemption execution
- **Idempotency**: Duplicate request protection
- **Rollback Capability**: Automatic reversal on failure
- **Data Consistency**: ACID compliance for state changes

#### Scalability Requirements
- **Data Volume**: Support millions of redemptions
- **Condition Complexity**: Handle 100+ conditions per reward
- **User Base**: Scale to 10M+ active users
- **Merchant Growth**: Multi-tenant isolation

#### Security Requirements
- **Function Security**: SECURITY DEFINER for controlled access
- **Eligibility Validation**: Pre-redemption authorization checks
- **Code Protection**: Unique promo code enforcement
- **Data Isolation**: Merchant-specific data segregation

#### Auditability Requirements
- **Complete Audit Trail**: All state transitions logged
- **Point Tracking**: Full transaction history with metadata
- **User Actions**: Detailed redemption timeline
- **System Events**: Fulfillment status changes

---

## System Architecture

### Architectural Overview

The Reward Redemption System is architected as a modular, event-driven platform with clear separation of concerns:

1. **Presentation Layer**: User interfaces for reward browsing and redemption
2. **Service Layer**: Business logic orchestration and validation
3. **Calculation Engine**: Dynamic points pricing and condition matching
4. **Data Layer**: Transactional storage with audit trails
5. **Integration Layer**: Cross-system coordination with Currency, Tier, and Persona systems

### High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "User Interface Layer"
        UI1[Mobile App]
        UI2[Web Portal]
        UI3[Admin Dashboard]
    end
    
    subgraph "API Layer"
        API1[Reward Catalog API]
        API2[Redemption API - Render]
        API3[Fulfillment API]
    end
    
    subgraph "Event Streaming Layer"
        ES1[Kafka: reward_redemptions topic]
        ES2[Event Processor Worker]
    end
    
    subgraph "Business Logic Layer"
        BL1[redeem_reward_with_points]
        BL2[Eligibility Validator]
        BL3[Points Calculator]
        BL4[Limit Enforcer]
        BL5[Promo Code Manager]
        BL6[Wallet Manager]
    end
    
    subgraph "Points Calculation Engine"
        PC1[calculate_redemption_points]
        PC2[Multi-Dimensional Matcher]
        PC3[Fallback Handler]
        PC4[Persona Validator]
    end
    
    subgraph "Data Layer"
        DL1[reward_master]
        DL2[reward_points_conditions]
        DL3[reward_redemptions_ledger]
        DL4[reward_promo_code]
        DL5[transaction_limits]
        DL6[user_wallet]
        DL7[wallet_ledger]
    end
    
    subgraph "Integration Layer"
        INT1[Currency System]
        INT2[Tier System]
        INT3[Persona System]
        INT4[Tag System]
        INT5[Notification Service]
        INT6[Supabase Realtime: postgres_changes + Broadcast]
    end
    
    UI1 --> API1
    UI1 --> API2
    UI2 --> API1
    UI2 --> API2
    UI3 --> API3
    
    API2 --> ES1
    ES1 --> ES2
    ES2 --> BL1
    
    API1 --> BL2
    API3 --> DL3
    
    BL1 --> BL2
    BL1 --> BL3
    BL1 --> BL4
    BL1 --> BL5
    BL1 --> BL6
    
    BL3 --> PC1
    PC1 --> PC2
    PC1 --> PC3
    PC1 --> PC4
    
    BL2 --> DL1
    BL2 --> INT2
    BL2 --> INT3
    BL2 --> INT4
    BL3 --> DL2
    BL4 --> DL5
    BL5 --> DL4
    BL6 --> DL6
    BL6 --> DL7
    
    DL3 --> INT6
    INT6 --> UI1
    INT6 --> UI2
    
    API3 --> INT5
    
    style UI1 fill:#e3f2fd
    style BL1 fill:#fff3e0
    style PC1 fill:#e8f5e9
    style DL1 fill:#e1f5fe
    style INT1 fill:#fce4ec
    style ES1 fill:#fff9c4
    style ES2 fill:#fff9c4
```

### Asynchronous Processing Model

The system uses an **event-driven architecture** for redemption processing to ensure reliability and scalability:

**Request Flow:**
1. Frontend → Render API (immediate response with `event_id`)
2. Render API → Kafka topic (`reward_redemptions`)
3. Event Processor → Consumes from Kafka
4. Event Processor → Calls Supabase RPC function (`redeem_reward_with_points`)
5. **On success**: Supabase creates ledger records → Supabase Realtime `postgres_changes` INSERT on `reward_redemptions_ledger` → Frontend receives success
6. **On failure**: Event Processor → Supabase Realtime **Broadcast** (HTTP) on channel `redemption:{user_id}` → Frontend receives error with title/description

**Frontend Notification Architecture:**
- **Success path**: Uses Supabase Realtime `postgres_changes` (INSERT on `reward_redemptions_ledger`) — triggered by the database write itself
- **Failure path**: Uses Supabase Realtime **Broadcast** (no database write) — the Event Processor sends an HTTP broadcast via `POST /realtime/v1/api/broadcast` with the error details
- **Timeout fallback**: Frontend applies a ~15s timeout — if neither success nor failure arrives, shows a generic "processing" message
- Broadcast is **ephemeral** (fire-and-forget, not persisted). If the user is not connected when the failure message is sent, they simply won't see it. This is safe because on failure, nothing changed in the database.

**Benefits:**
- **Non-blocking**: UI responds immediately (<50ms)
- **Reliable**: Kafka guarantees message delivery
- **Scalable**: Parallel processing of redemptions — 10k users hold WebSocket connections, not HTTP polls
- **Resilient**: Automatic retry on transient failures (up to 5 retries with exponential backoff)
- **Observable**: Full event trail for debugging
- **Complete feedback**: Both success AND failure are communicated to the frontend in real-time

### Component Relationships

#### Data Flow
1. **Catalog Browse**: User → API → Eligibility Check → Points Calculation → Display
2. **Redemption**: User → Validation → Points Deduction → Code Assignment → Ledger Entry
3. **Fulfillment**: Redemption → Status Update → Notification → Completion

#### Integration Points
- **Currency System**: Points balance and transaction management
- **Tier System**: Customer segmentation for eligibility
- **Persona System**: Business profile validation
- **Tag System**: Behavioral targeting
- **Notification Service**: Redemption confirmations

### Core Components

#### Redemption Service

**Function: `redeem_reward_with_points`**
- **Purpose**: Central orchestrator for reward redemption flow
- **Input**: User ID, Reward ID, optional delivery address
- **Processing**:
  1. Validate reward exists and is active
  2. Check comprehensive eligibility (tier, type, persona, tags)
  3. Calculate dynamic points using multi-dimensional matching
  4. Verify user has sufficient points
  5. Enforce redemption limits (user and global)
  6. Assign promo code from pool if required
  7. Deduct points via Currency System
  8. Create redemption ledger entry
  9. Initialize fulfillment tracking
- **Output**: Redemption ID, promo code (if applicable), points deducted

#### Points Calculation Engine

**Function: `calculate_redemption_points`**
- **Purpose**: Determine exact points required for specific user
- **Input**: Reward ID, User ID
- **Algorithm**:
  1. Gather user dimensions (tier, type, persona, tags)
  2. Retrieve all active conditions for reward
  3. Score conditions by specificity (4 dims > 3 dims > 2 dims > 1 dim)
  4. Apply priority weighting within same specificity
  5. Select lowest points at highest matched specificity
  6. Return fallback if no conditions match
- **Output**: Points required, matched condition ID, condition details

#### Eligibility Validator

**Function: `check_reward_eligibility_enhanced`**
- **Purpose**: Comprehensive eligibility verification
- **Input**: Reward ID, User ID
- **Validations**:
  - Tier membership (if restricted)
  - User type compatibility
  - Persona qualification with type consistency
  - Tag requirements (all required tags must be present)
  - Time window constraints
  - Birthday month (if applicable)
  - Stock availability
  - Promo code pool status
- **Output**: Eligibility status, rejection reasons, available quantity

#### Supporting Services

**Multi-Dimensional Matcher**:
- Evaluates conditions across tier, type, persona, and tag dimensions
- Implements specificity-based scoring algorithm
- Returns best match for user profile

**Promo Code Manager**:
- Atomic code assignment from pool
- Prevents duplicate assignment
- Handles default vs unique codes
- **Multi-Quantity Support**:
  - Reserves N codes atomically using `FOR UPDATE SKIP LOCKED`
  - Validates pool has sufficient codes before redemption
  - Creates separate ledger records for each unique code
  - All-or-nothing transaction (no partial redemptions)

**Limit Enforcer**:
- Validates against user redemption history
- Checks global redemption caps
- Enforces time-windowed restrictions

**Persona-Aware Validator**:
- Filters eligibility fields based on user's assigned persona
- Universal fields (no persona restriction) always apply
- Persona-specific fields only validated for matching users
- Prevents blocking users for irrelevant profile fields

---

## Database Schema

### Schema Design Principles

1. **Separation of Concerns**: Rewards, conditions, and redemptions in separate tables
2. **Audit Trail**: Complete history in ledger tables
3. **Idempotency**: Natural keys prevent duplicate operations
4. **Consistency**: Foreign key constraints maintain referential integrity
5. **Performance**: Optimized indexes for common query patterns
6. **Two-Layer Architecture**: Materialized views for aggregation, regular views for real-time data

### Core Tables

#### Table: `reward_master`
**Purpose**: Central repository for all reward definitions with comprehensive configuration

```sql
CREATE TABLE reward_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Basic Information
    name TEXT,
    description_headline TEXT,
    description_body TEXT,
    description_tc TEXT,        -- Terms & Conditions
    description_slip TEXT,       -- Redemption slip text
    image TEXT[],               -- Array of image URLs
    
    -- Categorization
    group_id UUID[],            -- Reward groups
    category_id UUID[],         -- Reward categories
    ranking SMALLINT,           -- Display order
    
    -- Eligibility Rules (Layer 1: WHO can redeem)
    allowed_tier UUID[],        -- Eligible tier IDs
    allowed_type UUID[],        -- Eligible user type IDs
    allowed_persona UUID[],     -- Eligible persona IDs (NEW)
    allowed_tags UUID[],        -- Required tag IDs (NEW)
    allowed_birthmonth TEXT[],  -- Eligible birth months (1-12)
    
    -- Points Configuration (Layer 2: HOW MANY points)
    fallback_points NUMERIC,    -- Default points if no condition matches (NEW)
    require_points_match BOOLEAN DEFAULT false, -- If true, must match a condition (NEW)
    
    -- Redemption Configuration
    visibility reward_visibility,
    redeem_window_start TIMESTAMPTZ,
    redeem_window_end TIMESTAMPTZ,
    
    -- Inventory & Codes
    stock_control BOOLEAN,
    assign_promocode BOOLEAN,
    promo_code TEXT,            -- Default promo code if not unique
    
    -- Expiration Settings
    use_expire_mode reward_expire_mode,
    use_expire_date TIMESTAMPTZ,    -- For absolute_date mode
    use_expire_ttl NUMERIC,          -- For relative modes
    
    -- Fulfillment
    fulfillment_method reward_fulfillment_method,
    
    -- Marketplace Distribution
    online_store TEXT[]              -- Storefronts to display on (e.g. 'shopify', 'bigcommerce', 'lazada')
);
```

#### 2. `reward_points_conditions` (NEW)
Dynamic points pricing conditions based on customer attributes.

```sql
CREATE TABLE reward_points_conditions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reward_id UUID NOT NULL REFERENCES reward_master(id) ON DELETE CASCADE,
    merchant_id UUID NOT NULL,
    
    -- Condition dimensions (all optional - NULL means any)
    tier_id UUID REFERENCES tier_master(id),
    user_type user_type,
    persona_id UUID REFERENCES persona_master(id),
    tag_ids UUID[],             -- Multiple tags can be required
    
    -- Points configuration
    points_required NUMERIC NOT NULL CHECK (points_required >= 0),
    priority INTEGER DEFAULT 100, -- Higher priority wins in conflicts
    
    -- Metadata
    condition_name TEXT,
    description TEXT,
    active_status BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint to prevent duplicate conditions
    UNIQUE(reward_id, tier_id, user_type, persona_id, tag_ids)
);
```

#### Table: `reward_redemptions_ledger`
**Purpose**: Complete audit trail of all redemption transactions with status tracking

```sql
CREATE TABLE reward_redemptions_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Redemption Details
    reward_id UUID REFERENCES reward_master(id),
    user_id UUID REFERENCES users(id),
    code TEXT,                  -- Unique redemption code (RWD000001)
    qty NUMERIC DEFAULT 1,
    
    -- Points Information (NEW)
    points_deducted NUMERIC,    -- Total points deducted
    points_calculation JSONB,   -- Calculation details
    
    -- Status Tracking
    redeemed_status BOOLEAN DEFAULT FALSE,
    redeemed_at TIMESTAMPTZ,
    used_status BOOLEAN DEFAULT FALSE,
    used_at TIMESTAMPTZ,
    use_expire_date TIMESTAMPTZ,
    
    -- Promo Code
    promo_code TEXT,            -- Assigned promo code if applicable
    
    -- Fulfillment
    fulfillment_status rewards_redemption_fulfillment_status,
    delivery_address_code TEXT
);
```

#### Table: `wallet_ledger` Integration
**Purpose**: Points transaction recording for redemption burns

```sql
-- Example entry for redemption
{
    "user_id": "uuid",
    "merchant_id": "uuid", 
    "currency": "points",
    "transaction_type": "burn",
    "component": "base",
    "amount": 100,
    "signed_amount": -100,
    "source_type": "reward_redemption",
    "source_id": "redemption_uuid",
    "metadata": {
        "reward_id": "uuid",
        "points_calculation": {...}
    }
}
```

### Additional Tables

#### Table: `reward_promo_code`
**Purpose**: Storage for unique promotional codes assigned to rewards

```sql
CREATE TABLE reward_promo_code (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Code Information
    promo_code TEXT,                -- The unique code
    name TEXT,                       -- Batch name for grouping
    lot_code TEXT,                   -- Lot identifier
    
    -- Assignment
    reward_id UUID REFERENCES reward_master(id),
    source_id UUID,                  -- Partner merchant ID if applicable
    
    -- Status
    redeemed_status BOOLEAN DEFAULT FALSE,
    
    -- Unique constraint
    UNIQUE(promo_code, merchant_id)
);
```

#### Table: `reward_promo_code_staging`
**Purpose**: Temporary storage for bulk promo code uploads before processing

```sql
CREATE TABLE reward_promo_code_staging (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Staging data
    promo_code TEXT,
    lot_code TEXT,
    name TEXT,
    
    -- Processing status
    processed BOOLEAN DEFAULT FALSE,
    error_message TEXT,
    
    -- Session tracking
    import_session_id UUID
);
```

#### Table: `partner_merchant`
**Purpose**: Partner/supplier information for promo code source tracking

```sql
CREATE TABLE partner_merchant (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL,
    partner_name TEXT NOT NULL,
    partner_code TEXT NOT NULL,
    active_status BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(merchant_id, partner_code)
);
```

---

## Promo Code Management

### Overview

The promo code system manages both default codes (shared across users) and unique codes (individually assigned). This dual-mode approach supports various business scenarios from mass promotions to exclusive partner distributions.

### Promo Code Architecture

**Default Promo Codes**: Stored in `reward_master.promo_code`, shared by all users redeeming the reward

**Unique Promo Codes**: Managed in `reward_promo_code` table with individual tracking:
- Pre-loaded codes from partners or suppliers
- Individual redemption status tracking
- Partner attribution for source analysis
- Batch management for bulk operations

### Two-Stage Status Tracking

The system tracks promo codes through two distinct phases:

**Redeemed Status** (`reward_promo_code.redeemed_status`):
- Set when code is assigned to a user during redemption
- Prevents duplicate assignment
- Triggered by `redeem_reward_with_points()` function

**Used Status** (`reward_redemptions_ledger.used_status`):
- Set when reward is actually consumed
- Tracks fulfillment completion
- Enables usage analytics and expiry management

### Data Access Views

**Individual Code View** (`v_reward_promo_code_list`):
- **Joins**: `reward_promo_code` → `reward_master`, `partner_merchant`, `reward_redemptions_ledger`
- **Purpose**: Real-time tracking of individual promo codes with their current status
- **Use Cases**: Code lookup, availability checking, partner attribution analysis

**Reward Summary View** (`v_reward_promo_code_summary`):
- **Architecture**: Three-layer design for performance + security:
  1. `mv_reward_promo_code_summary_internal` (materialized view) - Pre-aggregates millions of codes
  2. `get_promo_code_summary()` (SECURITY DEFINER function) - Applies merchant RLS filtering
  3. `v_reward_promo_code_summary` (regular view) - Clean API endpoint
- **Why Three Layers**: PostgreSQL doesn't allow RLS on materialized views. The internal MV provides 3000x faster aggregations, the function applies secure merchant filtering via JWT token, and the view provides a clean queryable endpoint
- **Refresh Strategy**: Cron job refreshes materialized view every 5 minutes (`refresh-promo-code-summary`)
- **Grouping**: Aggregates all promo codes by reward (`id` column = reward_id) - shows total codes per reward across all batches
- **Purpose**: Dashboard summaries showing reward totals, redemption rates, batch names array
- **Use Cases**: Inventory management per reward, overall reward performance analytics
- **Query**: `SELECT * FROM v_reward_promo_code_summary` (automatically filtered by your merchant_id from JWT)

### Bulk Upload System

The promo code system supports massive batch imports through specialized upload functions:

**Upload Functions**:
- `bulk_upload_promo_codes()`: Standard batch import with deduplication
- `bulk_upload_promo_codes_validated()`: Enhanced validation with detailed error reporting

**Upload Process**:
1. Codes validated for duplicates within merchant
2. Partner attribution if source_id provided
3. Batch metadata (name, lot_code) assigned
4. Atomic insertion ensures all-or-nothing
5. Materialized view refreshes automatically (max 5 minutes delay via cron)

**Performance**: Handles 100,000 codes in ~15 seconds with full validation

**Refresh Schedule**:
- **Automatic**: Cron job refreshes `mv_reward_promo_code_summary_internal` every 5 minutes
- **Manual**: Can trigger immediate refresh via `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_reward_promo_code_summary_internal`
- **Impact**: Summary view data may be up to 5 minutes stale (acceptable for inventory reporting)

---


### Upload Best Practices

1. **Validation First**: Always validate before insertion
2. **Duplicate Check**: Pre-check for existing codes
3. **Batch Naming**: Use descriptive batch names for tracking
4. **Partner Attribution**: Link codes to partner_merchant for source tracking
5. **Lot Codes**: Use for quality control and recall capability
6. **Progress Monitoring**: Implement progress callbacks for large uploads
7. **Error Recovery**: Save failed codes for retry
8. **Audit Trail**: Log all upload operations

### Performance Optimization

| Upload Size | Method | Processing Time | MV Refresh |
|------------|--------|-----------------|------------|
| < 1K codes | Direct | < 1 second | Immediate |
| 1K-10K | Chunked | 2-5 seconds | After completion |
| 10K-100K | Chunked | 10-30 seconds | Async queue |
| > 100K | Staging | 1-5 minutes | Scheduled |

---

## Cached Rewards API (`api_get_rewards_full_cached`)

### Overview

The `api_get_rewards_full_cached` function provides a high-performance endpoint for fetching complete reward catalog data with automatic Redis caching. This function is the primary consumer-facing API for reward browsing.

### Purpose

- **Single RPC call** returns all reward data including translations, stock, and redemption stats
- **5-minute Redis cache** per merchant for 99% cache hit rate in normal operation
- **Automatic invalidation** on any reward data change
- **Multi-language support** - all languages returned in single response for instant language switching
- **Transparent caching** - frontend unchanged, caching logic entirely backend-managed

### Function Design

**Signature:**
```sql
api_get_rewards_full_cached() → JSON
```

**Return Structure:**
```json
[
  {
    "id": "reward-uuid",
    "name": "Coffee Mug",
    "translations": {
      "en": { "name": "Coffee Mug", "headline": "...", "body": "..." },
      "th": { "name": "แก้ว", "headline": "...", "body": "..." },
      "ja": { "name": "マグカップ", "headline": "...", "body": "..." }
    },
    "points": { "fallback": 100 },
    "image": { "url": "https://..." },
    "availability": {
      "in_stock": true,
      "redeemed": 5
    },
    "promo_codes": {
      "enabled": false,
      "used": 0,
      "total": 0
    },
    "validity": {
      "start": "2025-01-01",
      "redemption_window_start": "2025-01-01",
      "redemption_window_end": "2026-12-31"
    },
    "visibility": "user"
  }
]
```

### Caching Strategy

**Cache Key:** `merchant:{merchant_id}:rewards:all_languages`

**TTL:** 5 minutes (300 seconds)

**Invalidation Triggers:**
- `reward_master` INSERT/UPDATE
- `translations` INSERT/UPDATE (reward type)
- `reward_stock` INSERT/UPDATE
- `reward_promo_code` INSERT/UPDATE
- `reward_redemptions_ledger` INSERT/UPDATE

### Frontend Usage

**REST API:**
```bash
curl -X POST https://project.supabase.co/rest/v1/rpc/api_get_rewards_full_cached \
  -H "Authorization: Bearer ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**JavaScript:**
```javascript
const { data, error } = await supabase
  .rpc('api_get_rewards_full_cached');

// All languages loaded in single call
// Switch language without new API call
const reward = data[0];
const name = reward.translations[userLanguage].name;
```

### Implementation Details

**Query Execution:**
1. Extract `merchant_id` from JWT token context
2. Check Redis for cache key
3. **Cache hit:** Return JSON immediately (2-5ms)
4. **Cache miss:** Execute complex PostgreSQL query:
   - Join `reward_master` with `translations`
   - Aggregate `reward_stock` for availability
   - Count `reward_redemptions_ledger` for redemption stats
   - Aggregate `reward_promo_code` usage
5. Store result in Redis with 5-min TTL
6. Return to frontend

**Performance:**
- Cache hit: 2-5ms
- Cache miss: 2-3ms (typical query)
- Effective response for 100+ merchants: ~3 DB queries/second (99.97% cache rate)

---

## Dynamic Points Calculation

### Multi-Dimensional Matching System

The system evaluates FOUR dimensions to determine points required:

```mermaid
graph TD
    subgraph "User Attributes"
        U1[Tier: Gold]
        U2[Type: Buyer]
        U3[Persona: Student]
        U4[Tags: VIP, Early Adopter]
    end
    
    subgraph "Matching Process"
        M1[Find All Conditions]
        M2[Evaluate Each Dimension]
        M3[Calculate Specificity]
        M4[Apply Priority Rules]
        M5[Select Best Match]
    end
    
    subgraph "Condition Examples"
        C1[Gold + Buyer + Student + VIP<br/>Specificity: 4<br/>Points: 5]
        C2[Gold + Buyer<br/>Specificity: 2<br/>Points: 15]
        C3[Any + VIP Tag<br/>Specificity: 1<br/>Points: 10]
        C4[Gold Tier Only<br/>Specificity: 1<br/>Points: 20]
    end
    
    subgraph "Result"
        R1[Selected: Condition 1<br/>Points Required: 5<br/>Most Specific Match]
    end
    
    U1 --> M1
    U2 --> M1
    U3 --> M1
    U4 --> M1
    
    M1 --> M2
    M2 --> M3
    M3 --> M4
    M4 --> M5
    
    C1 --> M2
    C2 --> M2
    C3 --> M2
    C4 --> M2
    
    M5 --> R1
    
    style U1 fill:#e3f2fd
    style R1 fill:#c8e6c9
```

### Matching Logic Rules

1. **Specificity First**: Conditions matching more dimensions take precedence
2. **Priority Tiebreaker**: When specificity is equal, higher priority wins
3. **Customer-Favorable**: When all else is equal, lowest points wins
4. **Fallback Mechanism**: When no conditions match, use fallback_points

### Calculation Flow

```mermaid
sequenceDiagram
    participant User
    participant System
    participant Calculator
    participant Conditions
    participant Fallback
    
    User->>System: Request Redemption
    System->>Calculator: calculate_redemption_points()
    
    Calculator->>Calculator: Get User Attributes
    Note over Calculator: Tier, Type, Persona, Tags
    
    Calculator->>Conditions: Find Matching Conditions
    Conditions->>Conditions: Evaluate All Dimensions
    
    alt Has Matching Conditions
        Conditions->>Conditions: Sort by Specificity
        Conditions->>Conditions: Apply Priority
        Conditions->>Conditions: Select Lowest Points
        Conditions-->>Calculator: Best Match Found
        Calculator-->>System: Points from Condition
    else No Match
        Calculator->>Fallback: Check Fallback Config
        alt Has Fallback Points
            Fallback-->>Calculator: Use Fallback Points
            Calculator-->>System: Fallback Points
        else Require Match = True
            Fallback-->>Calculator: No Fallback Allowed
            Calculator-->>System: Error: No Match
        else No Fallback, Not Required
            Fallback-->>Calculator: Free Redemption
            Calculator-->>System: 0 Points
        end
    end
    
    System->>User: Points Required Response
```

### Example Configurations

#### Tiered Pricing with Persona Bonuses

```sql
-- Base tier pricing
INSERT INTO reward_points_conditions (reward_id, tier_id, points_required, condition_name)
VALUES 
    ('reward_uuid', 'bronze_tier_uuid', 100, 'Bronze Rate'),
    ('reward_uuid', 'silver_tier_uuid', 80, 'Silver Rate'),
    ('reward_uuid', 'gold_tier_uuid', 60, 'Gold Rate'),
    ('reward_uuid', 'platinum_tier_uuid', 40, 'Platinum Rate');

-- Special persona rates
INSERT INTO reward_points_conditions (reward_id, persona_id, points_required, priority, condition_name)
VALUES 
    ('reward_uuid', 'student_persona_uuid', 50, 150, 'Student Discount'),
    ('reward_uuid', 'corporate_persona_uuid', 70, 150, 'Corporate Rate');

-- VIP override (highest priority)
INSERT INTO reward_points_conditions (reward_id, tag_ids, points_required, priority, condition_name)
VALUES 
    ('reward_uuid', ARRAY['vip_tag_uuid'], 30, 200, 'VIP Special');

-- Fallback for unmatched users
UPDATE reward_master 
SET fallback_points = 120, require_points_match = false
WHERE id = 'reward_uuid';
```

---

## Redemption Process Flow

### Complete Redemption Flow with Dynamic Points

```mermaid
sequenceDiagram
    participant U as User
    participant UI as UI Layer
    participant API as Redemption API
    participant RR as redeem_reward_with_points()
    participant EV as Eligibility Validator
    participant CP as calculate_redemption_points()
    participant LE as Limit Enforcer
    participant PM as Promo Manager
    participant WM as Wallet Manager
    participant DB as Database
    
    U->>UI: Select Reward
    UI->>API: Request Redemption
    API->>RR: redeem_reward_with_points(user_id, reward_id, qty)
    
    RR->>DB: Fetch Reward Details
    DB-->>RR: reward_master record
    
    RR->>DB: Fetch User Profile
    DB-->>RR: user with tier, type, persona, tags
    
    RR->>EV: Check Eligibility
    EV->>EV: Check Tier
    EV->>EV: Check User Type
    EV->>EV: Check Persona
    EV->>EV: Check Tags
    EV->>EV: Check Birth Month
    EV->>EV: Check Time Window
    EV-->>RR: Eligibility Result
    
    alt Not Eligible
        RR-->>API: Error: Not Eligible
        API-->>UI: Show Error
        UI-->>U: Display Reason
    else Eligible
        RR->>CP: Calculate Points
        CP->>CP: Get User Attributes
        CP->>CP: Find Conditions
        CP->>CP: Evaluate Dimensions
        CP->>CP: Apply Matching Logic
        CP-->>RR: Points Required
        
        RR->>WM: Check Balance
        WM->>DB: Get Points Balance
        DB-->>WM: Current Balance
        WM-->>RR: Balance Check Result
        
        alt Insufficient Points
            RR-->>API: Error: Need More Points
            API-->>UI: Show Required vs Available
            UI-->>U: Display Points Needed
        else Sufficient Points
            RR->>LE: Check Limits
            LE->>DB: Count Previous Redemptions
            DB-->>LE: Redemption Count
            LE->>LE: Calculate Window
            LE->>LE: Check Against Limits
            LE-->>RR: Limit Check Result
            
            alt Limit Exceeded
                RR-->>API: Error: Limit Exceeded
                API-->>UI: Show Limit Info
                UI-->>U: Display Remaining
            else Within Limits
                opt Promo Code Required
                    RR->>PM: Request Promo Code
                    PM->>DB: Get Available Code
                    DB-->>PM: Promo Code
                    PM->>DB: Mark as Redeemed
                    PM-->>RR: Assigned Code
                end
                
                RR->>RR: Calculate Expiration
                
                loop For Each Quantity
                    RR->>DB: Create Redemption Record
                    DB-->>RR: Redemption ID
                end
                
                RR->>WM: Deduct Points
                WM->>DB: Create Wallet Ledger Entry
                WM->>DB: Update Balance
                WM-->>RR: Deduction Success
                
                RR-->>API: Success Response
                API-->>UI: Redemption Details
                UI-->>U: Show Success
            end
        end
    end
```

### Multi-Quantity Redemption Implementation

The system supports redeeming multiple quantities of the same reward in a single transaction, with intelligent handling based on promo code requirements.

#### Architecture Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                │
│  POST /redemptions { reward_id, quantity: 5 }                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                    RENDER API (crm-api)                         │
│  1. Validate JWT (extract user_id, merchant_id)                │
│  2. Validate reward_id and quantity (1-1000)                   │
│  3. Publish to Kafka: { event_id, user_id, reward_id,         │
│                         quantity, merchant_id, timestamp }      │
│  4. Return: { success: true, event_id }                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓ (Kafka: reward_redemptions topic)
                             │
┌─────────────────────────────────────────────────────────────────┐
│               EVENT PROCESSOR (crm-event-processors)            │
│  1. Consume Kafka event                                         │
│  2. Extract: user_id, reward_id, quantity, merchant_id         │
│  3. Check idempotency (already processed?)                     │
│  4. Call Supabase RPC:                                          │
│     redeem_reward_with_points(                                  │
│       p_reward_id, p_quantity, p_user_id, p_merchant_id        │
│     )                                                            │
│  5. Handle retry on transient errors                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│          SUPABASE (redeem_reward_with_points function)          │
│  1. Validate eligibility (tier, persona, tags)                 │
│  2. Calculate points (multi-dimensional matching)              │
│  3. Check user balance                                          │
│  4. Branch based on promo codes:                                │
│                                                                  │
│     IF reward has promo codes:                                  │
│       ├─ Check pool availability (need N codes)                │
│       ├─ Reserve N codes atomically (FOR UPDATE SKIP LOCKED)   │
│       ├─ Create N ledger records (qty=1 each)                  │
│       ├─ Assign unique promo code to each                      │
│       └─ Mark each code as redeemed                            │
│                                                                  │
│     IF reward has NO promo codes:                               │
│       ├─ Create 1 ledger record (qty=N)                        │
│       └─ Use default promo code or NULL                        │
│                                                                  │
│  5. Deduct points via wallet system                            │
│  6. Return success with all redemption details                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Quantity Handling Patterns

**Pattern A: Reward WITHOUT Promo Codes**
- Creates **1 ledger record** with `qty = N`
- Single redemption code (e.g., RWD000123)
- Points deducted once: `points_per_unit × quantity`

**Example:**
```sql
-- Request: quantity = 5
-- Result: 1 record
id: evt-123
qty: 5
promo_code: NULL
points_deducted: 500
code: RWD000123
```

**Pattern B: Reward WITH Promo Codes**
- Creates **N ledger records** with `qty = 1` each
- Each record gets unique promo code from pool
- N redemption codes (e.g., RWD000123, RWD000124, ...)
- Atomic code reservation prevents conflicts

**Example:**
```sql
-- Request: quantity = 5
-- Result: 5 records

id: uuid-1, qty: 1, promo_code: 'CODE-ABC123', code: 'RWD000123'
id: uuid-2, qty: 1, promo_code: 'CODE-DEF456', code: 'RWD000124'
id: uuid-3, qty: 1, promo_code: 'CODE-GHI789', code: 'RWD000125'
id: uuid-4, qty: 1, promo_code: 'CODE-JKL012', code: 'RWD000126'
id: uuid-5, qty: 1, promo_code: 'CODE-MNO345', code: 'RWD000127'
```

**Pattern C: Insufficient Promo Codes**
- Transaction fails if pool has fewer codes than requested
- Returns clear error message with available count
- No partial redemptions - all or nothing

**Example:**
```sql
-- Request: quantity = 10, but only 7 codes available
-- Result: 1 failure record

id: evt-123
success: false
error_code: 'INSUFFICIENT_CODES'
error_message: 'Only 7 code(s) available, you requested 10'
```

#### API Request Format

```javascript
// POST to Render API
const response = await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${jwtToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'reward-uuid',
    quantity: 5,  // ✅ Supports 1-1000
  }),
});

// Immediate response (async processing)
{
  "success": true,
  "event_id": "event-uuid",
  "message": "Redemption request received and processing",
  "quantity": 5
}
```

#### Quantity Validation

- **Range:** 1-1000 per transaction
- **Validation:** Performed at Render API layer
- **Default:** quantity = 1 if omitted (backward compatible)
- **Invalid Values:** Return 400 error immediately

---

## Implementation Details

### Core Algorithms

#### Multi-Dimensional Points Matching Algorithm
```
Algorithm: Calculate Redemption Points
Input: reward_id, user_id
Output: points_required, matched_condition_id, calculation_metadata

1. Load user profile with dimensions:
   - tier_id from user_accounts
   - user_type from users table
   - persona_id from persona mapping
   - tag_ids from user_tags

2. Load all active conditions for reward:
   SELECT * FROM reward_points_conditions
   WHERE reward_id = ? AND active_status = true

3. Score each condition by specificity:
   specificity_score = 0
   if condition.tier_id matches: specificity_score += 1000
   if condition.user_type matches: specificity_score += 100
   if condition.persona_id matches: specificity_score += 10
   if condition.tag_ids subset of user.tag_ids: specificity_score += 1

4. Group conditions by specificity_score
   Sort groups descending by score

5. Within highest scoring group:
   - Apply priority ordering
   - Select condition with lowest points_required

6. If no conditions match:
   - Return reward.fallback_points if defined
   - Return null if require_points_match = true
   - Return 0 for free redemption otherwise
```

#### Idempotency Protection
```
Algorithm: Prevent Duplicate Redemptions
Input: user_id, reward_id, request_id
Output: redemption_id (existing or new)

1. Check for existing redemption with request_id:
   SELECT id FROM reward_redemptions_ledger
   WHERE metadata->>'request_id' = ?
   AND user_id = ? AND reward_id = ?
   AND created_at > NOW() - INTERVAL '24 hours'

2. If exists:
   Return existing redemption_id

3. If not exists:
   Proceed with new redemption
   Store request_id in metadata
```

### Security Patterns

#### Function Security
- All RPC functions use `SECURITY DEFINER`
- Row-level security on master tables
- Merchant isolation via `merchant_id` checks
- User validation before any operation

#### Data Validation
- Foreign key constraints for referential integrity
- Check constraints for business rules
- Trigger-based validation for complex rules
- Application-level validation before database operations

---

## Business Rules

### Core Business Rules

#### Dynamic Points Rules
1. **Multi-Dimensional Evaluation**: All four dimensions (tier, type, persona, tags) evaluated
2. **Specificity Priority**: More specific conditions override general ones
3. **Customer-Favorable**: Lowest points when multiple conditions match
4. **Fallback Handling**: Configurable default or free redemption

#### Redemption Rules
1. **Multi-Quantity Support**: Redemptions support quantities from 1 to 1000
   - Rewards WITHOUT promo codes: Creates 1 ledger record with qty=N
   - Rewards WITH promo codes: Creates N ledger records with unique codes (qty=1 each)
   - Atomic code reservation prevents race conditions
   - All-or-nothing: Transaction fails if insufficient promo codes available
2. **Positive Quantity**: Redemption quantity must be between 1 and 1000
3. **Window Enforcement**: Redemptions outside time windows are rejected
4. **Eligibility Priority**: All eligibility criteria must pass if specified
5. **Points Deduction**: Atomic wallet update with audit trail
6. **Promo Code Pool Validation**: Pre-checks availability for multi-quantity promo code rewards

#### Limit Rules
1. **Cumulative Counting**: Previous redemptions + new quantity checked against limit
2. **Window Calculation**: Time windows calculated from current time or specific dates
3. **Scope Independence**: User and global limits checked independently
4. **Remaining Disclosure**: System returns how many more redemptions allowed

#### Persona-Type Consistency
1. **Validation**: Persona must be compatible with user type
2. **Group Inheritance**: Persona groups can specify user type
3. **Conflict Prevention**: Incompatible combinations rejected

#### Persona-Aware Field Filtering

The eligibility system includes intelligent persona-aware filtering to ensure users are only validated against fields relevant to their assigned persona.

**Problem Solved:**
- Users with Persona A were being blocked for not filling fields restricted to Persona B
- Profile completion checks now filter fields based on user's actual persona
- Universal fields (no persona restriction) are always validated for all users

**Filtering Logic:**

| User Persona | Field `persona_ids` | Include in Validation? | Reason |
|--------------|---------------------|------------------------|--------|
| `persona-a` | `null` or `[]` | ✅ Yes | Universal field |
| `persona-a` | `[persona-a]` | ✅ Yes | Matches user persona |
| `persona-a` | `[persona-b]` | ❌ No | Different persona |
| `persona-a` | `[persona-a, persona-b]` | ✅ Yes | Includes user persona |
| `null` | `null` or `[]` | ✅ Yes | Universal field |
| `null` | `[persona-a]` | ❌ No | Restricted to persona |

**Implementation:**
```typescript
function filterFieldsByPersona(fields: any[], userPersonaId: string | null): any[] {
  return fields.filter(field => {
    // Universal fields (no persona restriction) → always visible
    if (!field.persona_ids || field.persona_ids.length === 0) {
      return true;
    }
    
    // User has no persona → skip persona-restricted fields
    if (!userPersonaId) {
      return false;
    }
    
    // User has persona → check if it matches
    return field.persona_ids.includes(userPersonaId);
  });
}
```

**Benefits:**
- Improved UX - users not blocked by irrelevant fields
- Accurate profile completion status per persona
- Maintains data integrity for persona-specific information

### Edge Cases & Handling

#### Concurrent Redemptions
- Row-level locking on promo codes
- Atomic wallet operations
- Transaction isolation for points deduction

#### Multiple Matching Conditions
- Specificity score calculation
- Priority-based selection
- Customer-favorable tiebreaker

#### No Matching Conditions
- Fallback points applied
- Free redemption if allowed
- Clear error if match required

---

## API Integration

### Calculate Points (Preview)
```http
GET /api/rewards/{reward_id}/points?user_id={user_id}
```

**Response**:
```json
{
  "reward_id": "uuid",
  "user_id": "uuid",
  "points_calculation": {
    "success": true,
    "points_required": 50,
    "match_type": "condition",
    "condition_name": "Gold VIP Rate",
    "match_details": {
      "tier_match": true,
      "type_match": false,
      "persona_match": false,
      "tags_match": true,
      "specificity": 2,
      "priority": 150
    },
    "user_attributes": {
      "tier": "Gold",
      "user_type": "buyer",
      "persona": "Student",
      "tags": ["VIP", "Early Adopter"]
    }
  },
  "user_eligible": true,
  "points_available": 500
}
```

### Redeem Reward
```http
POST /api/rewards/{reward_id}/redeem
```

**Request**:
```json
{
  "user_id": "uuid",
  "quantity": 5,
  "delivery_address_code": "addr_123"
}
```

**Response (Success - WITHOUT Promo Codes)**:
```json
{
  "success": true,
  "message": "Successfully redeemed 5 reward(s)",
  "redemption_codes": ["RWD000123"],
  "points_deducted": 250,
  "points_remaining": 250,
  "quantity": 5,
  "expires_at": "2024-02-01T23:59:59Z",
  "points_calculation": {
    "condition_matched": "Gold VIP Rate",
    "points_per_unit": 50,
    "total_points": 250
  }
}
```

**Response (Success - WITH Promo Codes)**:
```json
{
  "success": true,
  "message": "Successfully redeemed 5 reward(s)",
  "redemption_codes": ["RWD000123", "RWD000124", "RWD000125", "RWD000126", "RWD000127"],
  "promo_codes": ["CODE-ABC123", "CODE-DEF456", "CODE-GHI789", "CODE-JKL012", "CODE-MNO345"],
  "points_deducted": 250,
  "points_remaining": 250,
  "quantity": 5,
  "expires_at": "2024-02-01T23:59:59Z",
  "points_calculation": {
    "condition_matched": "Gold VIP Rate",
    "points_per_unit": 50,
    "total_points": 250
  }
}
```

**Response (Insufficient Points)**:
```json
{
  "success": false,
  "message": "Insufficient points. Required: 750, Available: 100",
  "points_required": 750,
  "points_available": 100,
  "quantity": 5,
  "points_calculation": {
    "condition_matched": "Silver Member Rate",
    "points_per_unit": 150,
    "total_points": 750
  }
}
```

**Response (Insufficient Promo Codes)**:
```json
{
  "success": false,
  "error_code": "INSUFFICIENT_CODES",
  "message": "Only 7 code(s) available, you requested 10",
  "available_codes": 7,
  "requested_quantity": 10
}
```

### Preview User Rewards
```http
GET /api/users/{user_id}/rewards/available
```

**Response**:
```json
{
  "rewards": [
    {
      "reward_id": "uuid",
      "name": "Premium Voucher",
      "points_required": 50,
      "match_type": "condition",
      "condition_name": "Gold VIP Rate",
      "user_eligible": true,
      "can_afford": true
    },
    {
      "reward_id": "uuid", 
      "name": "Exclusive Item",
      "points_required": 200,
      "match_type": "fallback",
      "user_eligible": true,
      "can_afford": false
    }
  ],
  "user_points_balance": 150
}
```

---

## API Integration

### RPC Functions

#### Core Redemption Functions

**`redeem_reward_with_points(user_id, reward_id, qty)`**:
- Orchestrates complete redemption flow
- Validates eligibility, calculates points, deducts balance
- Assigns promo codes from pool if configured
- Returns redemption details including codes and expiry

**`calculate_redemption_points(user_id, reward_id)`**:
- Preview points required without redeeming
- Shows matched condition and calculation details
- Useful for shopping cart displays

**`check_reward_eligibility_enhanced(user_id, reward_id)`**:
- Comprehensive eligibility validation
- Returns specific rejection reasons
- Checks tier, persona, tags, time windows, stock

#### Promo Code Management Functions

**`bulk_upload_promo_codes(codes[], reward_id, batch_name)`**:
- Batch import with automatic deduplication
- Supports partner attribution and lot codes
- Returns upload statistics and duplicate report

**`get_promo_code_summary()`**:
- Aggregated view of promo code batches
- Shows availability, redemption rates, partner performance
- Filtered by merchant context automatically

### REST API Endpoints

#### Get Available Rewards
```http
GET /rewards/available
Authorization: Bearer {token}

Response:
{
    "rewards": [
        {
            "id": "reward_uuid",
            "name": "Premium Voucher",
            "description": "Exclusive access voucher",
            "image_urls": ["https://..."],
            "points_required": 50,
            "eligibility": {
                "is_eligible": true,
                "can_afford": true
            },
            "availability": {
                "stock_remaining": 100,
                "user_limit_remaining": 3,
                "expires_in_days": 30
            },
            "fulfillment_method": "digital"
        }
    ],
    "user_balance": {
        "points": 500,
        "tier": "Gold",
        "persona": "Corporate"
    }
}
```

#### Redeem Reward
```http
POST /rewards/{reward_id}/redeem
Authorization: Bearer {token}
Content-Type: application/json

{
    "quantity": 1,
    "delivery_address_code": "addr_123",
    "request_id": "req_abc123"  // For idempotency
}

Response:
{
    "success": true,
    "redemption_id": "red_uuid",
    "redemption_code": "RWD000001",
    "promo_code": "SPECIAL2024",
    "points_deducted": 50,
    "new_balance": 450,
    "expires_at": "2024-12-31T23:59:59Z",
    "fulfillment": {
        "method": "digital",
        "status": "pending",
        "instructions": "Code will be sent via email"
    }
}
```

#### Get Redemption History
```http
GET /users/{user_id}/redemptions
Authorization: Bearer {token}

Response:
{
    "redemptions": [
        {
            "id": "red_uuid",
            "reward_name": "Premium Voucher",
            "redeemed_at": "2024-01-15T10:30:00Z",
            "points_spent": 50,
            "status": "redeemed",
            "promo_code": "SPECIAL2024",
            "expires_at": "2024-12-31T23:59:59Z",
            "fulfillment_status": "completed",
            "quantity": 1
        }
    ],
    "pagination": {
        "page": 1,
        "per_page": 20,
        "total_pages": 5,
        "total_count": 98
    }
}
```

#### Listen for Redemption Results (Realtime)

Since redemption processing is asynchronous, frontend subscribes to a **single Supabase Realtime channel** with two listeners — one for success (database INSERT) and one for failure (Broadcast):

```javascript
const channel = supabase.channel(`redemption:${userId}`)

// SUCCESS — Supabase Realtime postgres_changes on ledger INSERT
channel.on(
  'postgres_changes',
  {
    event: 'INSERT',
    schema: 'public',
    table: 'reward_redemptions_ledger',
    filter: `user_id=eq.${userId}`,
  },
  (payload) => {
    const redemption = payload.new;
    if (redemption.promo_code) {
      showSuccess(`Redeemed! Code: ${redemption.promo_code}`);
    } else {
      showSuccess(`Redeemed ${redemption.qty} item(s)!`);
    }
  }
)

// FAILURE — Supabase Realtime Broadcast (no database write, ephemeral)
// Event Processor sends this via HTTP when redemption fails validation
channel.on(
  'broadcast',
  { event: 'redemption_failed' },
  ({ payload }) => {
    // payload: { event_id, reward_id, title, description }
    showError(payload.title, payload.description);
    // e.g. "Personal redemption limit reached", "Limit: 1 per year. Used: 1."
  }
)

channel.subscribe()

// Timeout fallback — if neither event arrives within 15s
setTimeout(() => {
  if (!resultReceived) {
    showInfo('Redemption is being processed. Check your rewards history.');
  }
}, 15000);
```

**Broadcast payload shape** (sent by Event Processor on failure):
```json
{
  "event_id": "uuid",
  "reward_id": "uuid",
  "title": "Personal redemption limit reached",
  "description": "Limit: 1 per year. Used: 1. Requested: 1."
}
```

**For Multi-Quantity with Promo Codes**: Frontend will receive N separate INSERT events (one per unique code assigned).

**Important**: The failure broadcast is ephemeral — not stored anywhere. If the user disconnects before the message arrives, they won't see it. This is safe because failed redemptions make no database changes (no points deducted, no records created).

---

## Implementation Examples

### Example 1: Multi-Tier Pricing
**Scenario**: Reward with different points for each tier
- Bronze: 100 points
- Silver: 75 points
- Gold: 50 points
- Platinum: 30 points
- VIP Tag Override: 20 points

**Configuration**:
```sql
-- Tier-based conditions
INSERT INTO reward_points_conditions (reward_id, tier_id, points_required, condition_name)
VALUES 
    ('reward_uuid', 'bronze_uuid', 100, 'Bronze Rate'),
    ('reward_uuid', 'silver_uuid', 75, 'Silver Rate'),
    ('reward_uuid', 'gold_uuid', 50, 'Gold Rate'),
    ('reward_uuid', 'platinum_uuid', 30, 'Platinum Rate');

-- VIP override with higher priority
INSERT INTO reward_points_conditions (reward_id, tag_ids, points_required, priority, condition_name)
VALUES ('reward_uuid', ARRAY['vip_tag_uuid'], 20, 200, 'VIP Special');
```

### Example 2: Persona-Based Student Discount
**Scenario**: Students get special pricing
- Regular users: 100 points
- Students: 50 points
- Student VIPs: 30 points

**Configuration**:
```sql
-- Default for all users
UPDATE reward_master SET fallback_points = 100 WHERE id = 'reward_uuid';

-- Student discount
INSERT INTO reward_points_conditions (reward_id, persona_id, points_required, condition_name)
VALUES ('reward_uuid', 'student_persona_uuid', 50, 'Student Discount');

-- Student VIP (most specific)
INSERT INTO reward_points_conditions (reward_id, persona_id, tag_ids, points_required, priority, condition_name)
VALUES ('reward_uuid', 'student_persona_uuid', ARRAY['vip_tag_uuid'], 30, 150, 'Student VIP Rate');
```

### Example 3: Complex Multi-Dimensional Scenario
**User Profile**:
- Tier: Gold
- Type: Buyer
- Persona: Corporate
- Tags: [VIP, Frequent Buyer]

**Available Conditions**:
1. Gold + Buyer + Corporate + VIP: 40 points (Specificity: 4)
2. Gold + Corporate: 60 points (Specificity: 2)
3. Gold: 70 points (Specificity: 1)
4. VIP: 50 points (Specificity: 1)
5. Fallback: 100 points

**Result**: Condition 1 selected (40 points) - Most specific match

### Example 4: Redemption with Points Calculation
```sql
-- User redeems reward
SELECT redeem_reward_with_points(
    'user_uuid',
    'reward_uuid',
    1  -- quantity
);

-- Response includes calculation details
{
  "success": true,
  "redemption_ids": ["uuid"],
  "points_deducted": 40,
  "points_calculation": {
    "points_required": 40,
    "match_type": "condition",
    "condition_name": "Gold Corporate VIP Rate",
    "match_details": {
      "tier_match": true,
      "type_match": true,
      "persona_match": true,
      "tags_match": true,
      "specificity": 4
    }
  }
}
```

### Example 5: Multi-Quantity Redemption - No Promo Codes
**Scenario**: User redeems 5 coffee mugs (no unique codes required)
- User: Gold tier, 500 points available
- Points per mug: 100 points
- Total: 500 points

**Request**:
```javascript
fetch('/redemptions', {
  method: 'POST',
  body: JSON.stringify({
    reward_id: 'coffee-mug-uuid',
    quantity: 5
  })
});
```

**Database Result**:
```sql
-- Single record created
INSERT INTO reward_redemptions_ledger (
    id, user_id, reward_id, qty, points_deducted, code
) VALUES (
    'evt-123', 'user-uuid', 'coffee-mug-uuid', 5, 500, 'RWD000123'
);
```

**User Experience**: One redemption code (RWD000123) representing 5 mugs

### Example 6: Multi-Quantity Redemption - WITH Promo Codes
**Scenario**: User redeems 3 vouchers (each needs unique promo code)
- User: Gold tier, 300 points available
- Points per voucher: 100 points
- Promo code pool: 50 codes available

**Request**:
```javascript
fetch('/redemptions', {
  method: 'POST',
  body: JSON.stringify({
    reward_id: 'voucher-uuid',
    quantity: 3
  })
});
```

**Atomic Code Reservation**:
```sql
-- Supabase function executes
SELECT promo_code, id FROM reward_promo_code
WHERE reward_id = 'voucher-uuid' 
  AND redeemed_status = false
  AND merchant_id = 'merchant-uuid'
ORDER BY created_at
LIMIT 3
FOR UPDATE SKIP LOCKED;

-- Results: ['CODE-A', 'CODE-B', 'CODE-C']
```

**Database Result**:
```sql
-- Three records created, each with unique code
INSERT INTO reward_redemptions_ledger VALUES
  ('uuid-1', 'user-uuid', 'voucher-uuid', 1, 100, 'RWD000123', 'CODE-A'),
  ('uuid-2', 'user-uuid', 'voucher-uuid', 1, 100, 'RWD000124', 'CODE-B'),
  ('uuid-3', 'user-uuid', 'voucher-uuid', 1, 100, 'RWD000125', 'CODE-C');

-- Mark codes as redeemed
UPDATE reward_promo_code 
SET redeemed_status = true
WHERE promo_code IN ('CODE-A', 'CODE-B', 'CODE-C');
```

**User Experience**: Three separate vouchers with unique codes

### Example 7: Multi-Quantity with Insufficient Codes
**Scenario**: User requests 10 vouchers but only 7 codes available
- User: Has 1000 points (sufficient)
- Promo code pool: 7 codes remaining
- Request: 10 vouchers

**Request**:
```javascript
fetch('/redemptions', {
  method: 'POST',
  body: JSON.stringify({
    reward_id: 'voucher-uuid',
    quantity: 10
  })
});
```

**Result**:
```json
{
  "success": false,
  "error_code": "INSUFFICIENT_CODES",
  "message": "Only 7 code(s) available, you requested 10",
  "available_codes": 7,
  "requested_quantity": 10
}
```

**Behavior**:
- No points deducted
- No codes reserved
- No partial redemption
- Clear error message guides user to retry with quantity ≤ 7

---

## System Health & Monitoring

### Key Metrics to Monitor

#### Points Calculation Metrics
- Average calculation time
- Condition match rates
- Fallback usage frequency
- Most common condition matches

#### Redemption Metrics
- Total redemptions per day/hour
- Average points per redemption
- Points deducted by tier/persona
- Failed redemption attempts
- **Multi-Quantity Metrics**:
  - Quantity distribution (% with qty=1 vs qty>1)
  - Average quantity per redemption
  - Multi-quantity redemptions by reward type
  - Promo code pool depletion rate

#### Configuration Health
- Rewards without conditions
- Conditions without matches
- Conflicting persona-type configurations
- Unused conditions

### Health Check Queries

```sql
-- Check points configuration coverage
SELECT * FROM v_points_conditions_coverage;

-- Monitor points calculation performance
SELECT 
    reward_id,
    AVG(calculation_time_ms) as avg_time,
    COUNT(*) as calculations,
    SUM(CASE WHEN match_type = 'fallback' THEN 1 ELSE 0 END) as fallback_count
FROM redemption_metrics
WHERE created_at >= NOW() - INTERVAL '24 hours'
GROUP BY reward_id;

-- Analyze condition usage
SELECT 
    rpc.condition_name,
    COUNT(DISTINCT rrl.user_id) as unique_users,
    SUM(rrl.points_deducted) as total_points,
    AVG(rrl.points_deducted) as avg_points
FROM reward_redemptions_ledger rrl
JOIN reward_points_conditions rpc ON rpc.id = (rrl.points_calculation->>'condition_id')::uuid
WHERE rrl.created_at >= NOW() - INTERVAL '7 days'
GROUP BY rpc.condition_name
ORDER BY unique_users DESC;

-- Monitor multi-quantity redemption patterns
SELECT 
    r.name as reward_name,
    COUNT(*) as total_redemptions,
    SUM(rrl.qty) as total_units_redeemed,
    AVG(rrl.qty) as avg_quantity,
    COUNT(CASE WHEN rrl.qty > 1 THEN 1 END) as multi_qty_redemptions,
    ROUND(100.0 * COUNT(CASE WHEN rrl.qty > 1 THEN 1 END) / COUNT(*), 2) as multi_qty_percentage
FROM reward_redemptions_ledger rrl
JOIN reward_master r ON r.id = rrl.reward_id
WHERE rrl.created_at >= NOW() - INTERVAL '7 days'
  AND rrl.redeemed_status = true
GROUP BY r.id, r.name
ORDER BY total_units_redeemed DESC;

-- Monitor promo code pool health (alert when low)
SELECT 
    r.name as reward_name,
    COUNT(*) as total_codes,
    COUNT(CASE WHEN rpc.redeemed_status = false THEN 1 END) as available_codes,
    COUNT(CASE WHEN rpc.redeemed_status = true THEN 1 END) as used_codes,
    ROUND(100.0 * COUNT(CASE WHEN rpc.redeemed_status = true THEN 1 END) / COUNT(*), 2) as usage_percentage
FROM reward_promo_code rpc
JOIN reward_master r ON r.id = rpc.reward_id
WHERE r.assign_promocode = true
GROUP BY r.id, r.name
HAVING COUNT(CASE WHEN rpc.redeemed_status = false THEN 1 END) < 50
ORDER BY available_codes ASC;
```

---

## Conclusion

The enhanced Reward Redemption System with dynamic points calculation provides merchants with unprecedented flexibility in reward pricing strategies. The multi-dimensional matching system enables sophisticated customer segmentation while maintaining performance and simplicity. 

Key advantages of the system:
1. **Personalized Pricing**: Different points for different customer segments
2. **Flexible Configuration**: Easy to add/modify conditions without code changes
3. **Customer-Favorable**: Automatic selection of best rates for customers
4. **Complete Integration**: Seamless integration with persona and tag systems
5. **Comprehensive Audit**: Full tracking of points calculations and deductions
6. **Multi-Quantity Support**: Efficient handling of bulk redemptions with intelligent promo code allocation
7. **Persona-Aware Filtering**: Smart eligibility validation that only checks relevant profile fields per user persona

The system's architecture ensures accuracy through atomic operations, scales via optimized queries and indexes, and maintains complete audit trails for all transactions including dynamic points calculations.

---

## Appendices

### A. Error Codes and Messages

| Code | Message | Description |
|------|---------|-------------|
| RWD001 | Reward not found | Invalid reward ID |
| RWD002 | User not found | Invalid user ID |
| RWD003 | Invalid quantity | Quantity <= 0 |
| RWD004 | Outside redemption window | Current time outside allowed period |
| RWD005 | Tier not eligible | User's tier not in allowed list |
| RWD006 | Type not eligible | User's type not in allowed list |
| RWD007 | Persona not eligible | User's persona not in allowed list |
| RWD008 | Tags not eligible | User missing required tags |
| RWD009 | Birth month not eligible | Not user's birthday month |
| RWD010 | User limit exceeded | Per-user redemption limit reached |
| RWD011 | Global limit exceeded | Total redemption limit reached |
| RWD012 | No promo codes available | Promo code pool exhausted |
| RWD013 | Insufficient promo codes | Not enough unique codes in pool for quantity |
| RWD014 | Insufficient points | Not enough points for redemption |
| RWD015 | No matching points configuration | Required match but no conditions met |
| RWD016 | Persona-type conflict | Persona incompatible with user type |
| RWD017 | Invalid quantity | Quantity must be between 1 and 1000 |

### B. Database Indexes

Recommended indexes for performance:

```sql
-- Redemption lookups
CREATE INDEX idx_redemptions_user_reward 
ON reward_redemptions_ledger(user_id, reward_id, created_at);

-- Points conditions
CREATE INDEX idx_rpc_reward ON reward_points_conditions(reward_id) 
WHERE active_status = true;
CREATE INDEX idx_rpc_lookup ON reward_points_conditions(reward_id, tier_id, user_type, persona_id);

-- Promo code availability
CREATE INDEX idx_promo_codes_available 
ON reward_promo_code(reward_id, redeemed_status) 
WHERE redeemed_status = false;

-- Limit checking
CREATE INDEX idx_limits_entity 
ON transaction_limits(entity_type, entity_id);

-- Fulfillment tracking
CREATE INDEX idx_redemptions_fulfillment 
ON reward_redemptions_ledger(fulfillment_status) 
WHERE fulfillment_status != 'completed';
```

---

## Quick Reference

### Multi-Quantity Redemption Cheat Sheet

| Scenario | Quantity | Promo Codes | Ledger Records | Response |
|----------|----------|-------------|----------------|----------|
| Standard reward | 5 | No | 1 record (qty=5) | 1 redemption code |
| Voucher with codes | 5 | Yes | 5 records (qty=1 each) | 5 unique promo codes |
| Insufficient codes | 10 | Yes (7 available) | 0 records | Error: Only 7 available |
| Invalid quantity | 0 or 101 | Any | 0 records | 400 validation error |

### Persona Filtering Quick Reference

| Profile Field Type | User Has Persona | User No Persona | Validation Rule |
|-------------------|------------------|-----------------|-----------------|
| Universal (no restriction) | ✅ Always validate | ✅ Always validate | Required for everyone |
| Persona A only | ✅ Validate if user = A<br>❌ Skip if user ≠ A | ❌ Skip | Only for matching persona |
| Persona A or B | ✅ Validate if user = A or B<br>❌ Skip if user ≠ A,B | ❌ Skip | For multiple personas |

### API Response Quick Reference

**Immediate Response (Render API):**
```json
{
  "success": true,
  "event_id": "evt-uuid",
  "quantity": 5
}
```

**Async Result — Success (Supabase Realtime `postgres_changes` INSERT on `reward_redemptions_ledger`):**
```javascript
// For rewards without promo codes (1 event)
{ "redemption_code": "RWD000123", "qty": 5 }

// For rewards with promo codes (N events)
{ "redemption_code": "RWD000123", "promo_code": "CODE-A", "qty": 1 }
{ "redemption_code": "RWD000124", "promo_code": "CODE-B", "qty": 1 }
// ... (3 more events)
```

**Async Result — Failure (Supabase Realtime Broadcast on channel `redemption:{user_id}`):**
```json
{
  "event_id": "136c2592-a78c-48f3-a852-f32b7a57167e",
  "reward_id": "b042e084-71fa-46e0-b2bd-a2fa3ffb6b39",
  "title": "Personal redemption limit reached",
  "description": "Limit: 1 per year. Used: 1. Requested: 1."
}
```

---

## Conclusion

### System Strengths

1. **Multi-Dimensional Flexibility**: Dynamic points pricing adapts to any customer segmentation strategy
2. **Complete Lifecycle Management**: From creation through redemption to fulfillment tracking
3. **Merchant Autonomy**: Self-service configuration without technical intervention
4. **Audit Completeness**: Full transaction history with rollback capability
5. **Performance Optimization**: Sub-second redemption with concurrent handling

### Integration Benefits

- **Currency System**: Seamless points management with automatic balance updates
- **Tier System**: Deep integration for customer segmentation
- **Persona System**: Business profile-based targeting
- **Tag System**: Behavioral and preference-based personalization

### Future Considerations

#### Planned Enhancements
1. **Bundle Rewards**: Multiple items in single redemption
2. **Progressive Unlocking**: Staged reward availability based on achievements
3. **Social Redemptions**: Group or referral-based rewards
4. **Dynamic Inventory**: Real-time stock synchronization with external systems
5. **AI-Powered Recommendations**: Personalized reward suggestions

#### Scalability Roadmap
- **Distributed Caching**: Redis integration for condition matching
- **Event Streaming**: Kafka for real-time fulfillment updates
- **Microservice Extraction**: Separate fulfillment service
- **Global Distribution**: Multi-region deployment support

### Technical Debt Management
- Regular index optimization based on query patterns
- Archival strategy for historical redemption data
- Performance monitoring for multi-dimensional matching
- Periodic review of unused conditions and rewards

### Best Practices

1. **Condition Design**:
   - Start simple with tier-based conditions
   - Add dimensions incrementally based on business needs
   - Monitor condition effectiveness through analytics

2. **Points Strategy**:
   - Set clear fallback points for all rewards
   - Use priority wisely to control override behavior
   - Regular review of points economics

3. **Fulfillment Management**:
   - Clear SLAs for each fulfillment method
   - Automated status updates via webhooks
   - Proactive monitoring of failed fulfillments

4. **User Experience**:
   - Clear communication of points requirements
   - Real-time eligibility feedback
   - Transparent redemption limits

5. **Multi-Quantity Redemptions**:
   - Monitor promo code pool levels (alert when < 50 codes)
   - Track quantity distribution patterns
   - Implement proactive pool replenishment
   - Test with varying quantities before production

6. **Persona Management**:
   - Ensure profile fields are properly tagged with persona restrictions
   - Validate persona-type consistency in configuration
   - Monitor profile completion rates by persona
   - Keep universal fields to minimum for better UX

---

## Implementation Status

### Multi-Quantity Redemption
**Status:** ✅ **Deployed to Production**  
**Implementation Date:** February 3, 2026  
**Services Updated:**
- Supabase Function: `redeem_reward_with_points` - supports quantity parameter (1-1000)
- Render API (`crm-api`): Validates and passes quantity through Kafka
- Event Processor (`crm-event-processors`): Extracts quantity from events

**Key Features:**
- Smart branching: Single record for non-promo rewards, multiple records for promo code rewards
- Atomic promo code reservation with `FOR UPDATE SKIP LOCKED`
- All-or-nothing transaction semantics
- Backward compatible (quantity defaults to 1)

### Persona-Aware Field Filtering
**Status:** ✅ **Deployed to Production**  
**Implementation Date:** February 8, 2026  
**Function:** `bff-auth-complete` (Edge Function v54)

**Key Features:**
- Filters profile completion checks by user's assigned persona
- Universal fields always validated for all users
- Persona-restricted fields only checked for matching users
- Improved UX - users not blocked by irrelevant profile fields

**Monitoring:**
- Log entries: `[PERSONA_FILTER] User persona: <uuid>`
- Success metric: More users reaching `next_step: "complete"`
- Profile completion rates tracked per persona

### Promo Code Redemption UUID Fix
**Status:** ✅ **Deployed to Production**  
**Implementation Date:** February 16, 2026  
**Migration:** `fix_promo_code_redemption_uuid`  
**Function:** `redeem_reward_with_points()` - Fixed UUID generation for event-based idempotency

**Issue Resolved:**
- **Bug**: Event processor failed with `invalid input syntax for type uuid` when redeeming promo code rewards
- **Root Cause**: Function attempted to create UUID by appending suffix (e.g., `event_id-1`) for quantity loops
- **Impact**: 100% failure rate for rewards with `assign_promocode = true`

**Fix Implementation:**

**1. Added Business Rule Validation:**
```sql
-- Enforce single quantity for promo code rewards
IF v_reward.assign_promocode AND p_quantity > 1 THEN
    RETURN jsonb_build_object(
        'success', false,
        'title', 'Invalid quantity for promo code reward',
        'description', 'Rewards with unique promo codes can only be redeemed one at a time.'
    );
END IF;
```

**2. Fixed UUID Generation Logic:**
```sql
-- Before (Buggy):
v_record_id := (p_event_id::text || '-' || i)::uuid;  -- Invalid format!

-- After (Fixed):
IF p_event_id IS NOT NULL AND v_reward.assign_promocode THEN
    v_record_id := p_event_id;  -- Use event_id directly (qty always 1)
ELSIF p_event_id IS NOT NULL THEN
    v_record_id := (p_event_id::text || '-' || i)::uuid;  -- Multi-qty non-promo
ELSE
    v_record_id := gen_random_uuid();  -- Fallback
END IF;
```

**Key Technical Details:**

**Event-Driven Idempotency Pattern:**
- Render API generates `event_id` (UUID) and publishes to Kafka
- Event processor passes `event_id` as `p_event_id` to Supabase function
- Function uses `event_id` as the redemption record ID for idempotency
- Duplicate events return existing record instead of creating new one

**Promo Code Assignment Flow (Atomic Transaction):**
```sql
BEGIN;
    -- 1. SELECT and LOCK available code
    SELECT id, promo_code FROM reward_promo_code
    WHERE reward_id = $1 AND redeemed_status = false
    LIMIT 1 FOR UPDATE SKIP LOCKED;
    
    -- 2. UPDATE promo code status
    UPDATE reward_promo_code 
    SET redeemed_status = true 
    WHERE id = $1;
    
    -- 3. INSERT redemption record
    INSERT INTO reward_redemptions_ledger (
        id, promo_code, ...
    ) VALUES (
        p_event_id,  -- Use event_id directly
        $promo_code, -- Assigned code
        ...
    );
COMMIT;
```

**UUID Generation Rules:**
- **Promo code rewards (qty=1)**: Use `p_event_id` directly
- **Standard rewards (qty=1)**: Use `p_event_id` directly  
- **Standard rewards (qty>1)**: Use `p_event_id` with suffix if provided, else `gen_random_uuid()`
- **Direct calls (no event_id)**: Always use `gen_random_uuid()`

**Error Handling:**
- **Transient errors** (network, locks): Retry with exponential backoff (max 5 attempts)
- **Permanent errors** (validation, eligibility, insufficient codes): No retry, return error immediately
- **Concurrent conflicts**: `SKIP LOCKED` prevents deadlocks, moves to next available code

**Testing Results:**
- Promo code redemptions: ✅ Fixed (was 100% failure, now 100% success)
- Standard redemptions: ✅ Unchanged (0% regression)
- Processing time: ~100-200ms per redemption
- Concurrent safety: ✅ Multiple users can redeem simultaneously

**Monitoring:**
- Render logs: `[RewardConsumer] Successfully processed event {id} in {time}ms`
- Database: Promo codes marked as `redeemed_status = true`
- Redemption ledger: Promo codes populated in `promo_code` field

---

### Shopify Discount Product Lookup
**Status:** ✅ **Deployed to Production**  
**Implementation Date:** March 13, 2026  
**Functions:**
- `shopify-get-discount-products` (Edge Function) — Core Shopify product lookup
- `bff-mark-redemption-used` (Edge Function) — Wraps `api_mark_redemption_used` + Shopify enrichment
- `bff-get-redemption-detail` (Edge Function) — Redemption detail query + Shopify enrichment

**Purpose:**
For rewards linked to a Shopify discount (via `reward_master.external_id_shopify`), fetch the actual product details from the Shopify Price Rule — product names, images, prices, and discount type — and include them in the "mark as used" and "get redemption detail" responses.

**Architecture:**
```
bff-mark-redemption-used ──┐
                           ├──→ shopify-get-discount-products ──→ Shopify REST API
bff-get-redemption-detail ─┘
```

Both BFF functions call `shopify-get-discount-products` centrally. All Shopify logic (credential lookup, Price Rule fetch, product fetch, response mapping) lives in one function.

**How It Works:**
1. BFF function executes its primary operation (mark as used / query ledger)
2. Checks `reward_master.external_id_shopify` — if null, skip (zero overhead for non-Shopify rewards)
3. Calls `shopify-get-discount-products` with `merchant_id` + `reward_id`
4. `shopify-get-discount-products`:
   - Looks up Shopify credentials from `merchant_credentials` (service_name = `shopify_app`)
   - Calls Shopify REST API `GET /price_rules/{id}.json` to get discount details
   - Determines discount type: `free_product`, `percentage`, `fixed_amount`, or `free_shipping`
   - If entitled products exist: calls `GET /products.json?ids=...` for product details
   - If entitled collections exist: calls `GET /collections/{id}/products.json` for each
   - If `target_selection = "all"` or `target_type = "shipping_line"`: returns `has_products: false` (bill-level discount)
5. Product details merged into BFF response as `shopify_discount_detail`

**Shopify Discount Type Handling:**

| Scenario | `target_selection` | `target_type` | `has_products` | `discount_type` |
|---|---|---|---|---|
| Bill discount (% or fixed) | `all` | `line_item` | `false` | `percentage` / `fixed_amount` |
| Free shipping | `all` | `shipping_line` | `false` | `free_shipping` |
| 100% off specific products | `entitled` | `line_item` | `true` | `free_product` |
| % or fixed off specific products | `entitled` | `line_item` | `true` | `percentage` / `fixed_amount` |
| Collection discount | `entitled` | `line_item` | `true` | `percentage` / `fixed_amount` |

**Response Format (`shopify_discount_detail`):**
```json
{
  "success": true,
  "has_products": true,
  "discount_type": "free_product",
  "discount_value": "100",
  "target_all_items": false,
  "products": [
    {
      "shopify_product_id": 7897397755,
      "title": "Mini gift voucher",
      "image_url": "https://cdn.shopify.com/...",
      "variants": [
        {
          "variant_id": 6798798798,
          "title": "Default",
          "price": "200.00",
          "compare_at_price": "200.00"
        }
      ]
    }
  ],
  "collections": []
}
```

**API Endpoints:**

| Endpoint | Purpose | Auth |
|---|---|---|
| `POST /functions/v1/bff-mark-redemption-used` | Mark redemption used + Shopify products | User JWT |
| `POST /functions/v1/bff-get-redemption-detail` | Get redemption detail + Shopify products | User JWT |
| `POST /functions/v1/shopify-get-discount-products` | Internal: Shopify product lookup | Service Role Key |

**Key Design Decisions:**
- **On-demand**: Product details are fetched live from Shopify on every request — no data stored in the CRM database
- **Centralized**: Single `shopify-get-discount-products` function for all Shopify lookups
- **Graceful fallback**: If Shopify API is down or credentials missing, the response still works — `shopify_discount_detail` is simply absent
- **Zero overhead for non-Shopify rewards**: Shopify lookup only fires when `external_id_shopify` is set
- **REST API**: Uses Shopify REST Admin API (version 2024-04) consistent with existing `shopify-create-discount-code`

**Dependencies:**
- `merchant_credentials` table (service_name = `shopify_app`) for `shop_domain` and `access_token`
- `reward_master.external_id_shopify` for the Shopify Price Rule ID
- Shopify REST Admin API access scopes: `read_price_rules`, `read_products`, `read_collections`

---

*Document Version: 3.2*  
*Last Updated: March 13, 2026*  
*System: Supabase CRM - Reward Redemption System with Dynamic Points, Multi-Quantity, Persona Filtering, Fixed Promo Code Processing, and Shopify Product Lookup*