# Activity Auto-Populated Fields Feature

## Overview

Auto-populated fields automatically fetch user profile data from the USER_PROFILE form when users upload activities. This feature enables dynamic currency awards based on user attributes (tier, outlet, demographics, etc.) while reducing manual data entry for admins.

**Integration with Activity-Based Earning System:**
- Extends existing `activity_master.field_definitions` structure
- Pre-populates `activity_upload_ledger.field_values` at upload time
- Merges with admin-entered values at approval time
- Works seamlessly with existing currency matrix configuration

**Key Benefits:**
- ✅ Automatic user context capture at upload time
- ✅ Enable tier-based or outlet-based reward matrices
- ✅ Reduce admin manual entry (only fill activity-specific fields)
- ✅ Ensure data accuracy (pulled from verified user profile)
- ✅ Complete audit trail (all values stored in field_values)
- ✅ Profile completion enforcement (error if required fields missing)

---

## Field Type System

### Field Types

| Type | When Filled | By Whom | Source | Use Case |
|------|-------------|---------|--------|----------|
| `manual` | At approval | Admin | Dropdown selection | Activity-specific data (exercise type, time, etc.) |
| `auto_populate` | At upload | System | USER_PROFILE form_responses | User attributes (tier, outlet, demographics) |

### Field Definition Structure

**Manual Fields:**
```json
{
  "exercise_type": {
    "type": "manual",
    "label": "Type of Exercise",
    "options": ["yoga", "running", "swimming", "cycling"],
    "required": true,
    "order": 1
  },
  "time_of_day": {
    "type": "manual",
    "label": "Time of Day",
    "options": ["morning", "afternoon", "evening"],
    "required": true,
    "order": 2
  }
}
```

**Auto-Populated Fields:**
```json
{
  "user_tier": {
    "type": "auto_populate",
    "label": "User Tier",
    "field_key": "membership_tier",
    "required": true,
    "order": 3
  },
  "user_outlet": {
    "type": "auto_populate",
    "label": "User Branch",
    "field_key": "preferred_outlet",
    "required": false,
    "order": 4
  },
  "user_interest": {
    "type": "auto_populate",
    "label": "User Interests",
    "field_key": "interests",
    "required": false,
    "order": 5
  }
}
```

### Field Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | TEXT | Yes | Field type (free text for flexibility) |
| `label` | TEXT | Yes | Display label for UI |
| `field_key` | TEXT | Yes (auto) | Form field key from USER_PROFILE form |
| `options` | TEXT[] | Yes (manual) | Dropdown options for manual fields |
| `required` | BOOLEAN | Yes | Whether field must have a value |
| `order` | INTEGER | Yes | Display order in UI |

**Important Notes:**
- `type` is free text (not enum) for future extensibility
- No `source` field needed - auto-populated fields always pull from USER_PROFILE form
- `field_key` maps to `form_fields.field_key` in USER_PROFILE form
- Auto-populated values fetched from `form_responses` table

---

## Database Functions

### Helper Function: `fn_get_user_form_values()`

**Purpose:** Fetch user's custom field values from USER_PROFILE form

**Signature:**
```sql
CREATE OR REPLACE FUNCTION fn_get_user_form_values(
  p_user_id UUID,
  p_merchant_id UUID,
  p_field_keys TEXT[]
) RETURNS TABLE (
  field_key TEXT,
  field_value TEXT,
  is_array BOOLEAN
)
```

**Implementation:**
```sql
CREATE OR REPLACE FUNCTION fn_get_user_form_values(
  p_user_id UUID,
  p_merchant_id UUID,
  p_field_keys TEXT[]
) RETURNS TABLE (
  field_key TEXT,
  field_value TEXT,
  is_array BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ff.field_key,
    CASE 
      WHEN fr.text_value IS NOT NULL THEN fr.text_value
      WHEN fr.array_value IS NOT NULL THEN fr.array_value::text
      WHEN fr.object_value IS NOT NULL THEN fr.object_value::text
      ELSE NULL
    END as field_value,
    (fr.array_value IS NOT NULL) as is_array
  FROM form_templates ft
  JOIN form_field_groups ffg ON ffg.form_id = ft.id
  JOIN form_fields ff ON ff.group_id = ffg.id
  LEFT JOIN form_submissions fs ON fs.form_id = ft.id 
    AND fs.user_id = p_user_id
    AND fs.merchant_id = p_merchant_id
  LEFT JOIN form_responses fr ON fr.submission_id = fs.id 
    AND fr.field_id = ff.id
  WHERE ft.code = 'USER_PROFILE'
    AND ft.merchant_id = p_merchant_id
    AND ft.status = 'published'
    AND ff.field_key = ANY(p_field_keys);
END;
$$ LANGUAGE plpgsql STABLE;
```

**Example Usage:**
```sql
-- Fetch user's tier, outlet, and interests
SELECT * FROM fn_get_user_form_values(
  '123e4567-e89b-12d3-a456-426614174000',  -- user_id
  '987fcdeb-51a2-43f7-b123-456789abcdef',  -- merchant_id
  ARRAY['membership_tier', 'preferred_outlet', 'interests']
);

-- Returns:
-- field_key          | field_value    | is_array
-- -------------------+----------------+---------
-- membership_tier    | Gold Member    | false
-- preferred_outlet   | Central Branch | false
-- interests          | ["fitness","wellness"] | true
```

**Return Value Handling:**
- `text_value`: Single-select or free text fields
- `array_value`: Multi-select fields (returned as JSON string)
- `object_value`: Complex structured data (returned as JSON string)
- `NULL`: Field not filled by user or form_submission doesn't exist

---

### Modified Function: `upload_activity_image()`

**Key Changes:**
1. Extract auto_populate field definitions from activity config
2. Fetch values from form_responses via `fn_get_user_form_values()`
3. Validate required auto fields are not missing
4. Store auto-populated values in `field_values` column
5. Return auto-populated values in response

**New Logic Flow:**
```
1. Get current user & merchant context
2. Check frequency limits ← Existing
3. Get activity field_definitions
4. Extract auto_populate fields → NEW
5. Fetch form values for those fields → NEW
6. Validate required fields not missing → NEW
7. Create upload with auto values → NEW
8. Return success with auto values → NEW
```

**Pseudocode:**
```sql
-- Extract auto_populate field keys
SELECT 
  array_agg(key) as activity_keys,
  array_agg(value->>'field_key') as form_keys
INTO v_auto_field_keys, v_form_field_keys
FROM jsonb_each(v_field_definitions)
WHERE value->>'type' = 'auto_populate';

-- Fetch values from form_responses
SELECT jsonb_object_agg(activity_field_key, form_value)
INTO v_auto_values
FROM (
  SELECT 
    unnest(v_auto_field_keys) as activity_field_key,
    unnest(v_form_field_keys) as form_field_key
) mapping
LEFT JOIN LATERAL (
  SELECT field_value as form_value
  FROM fn_get_user_form_values(
    v_user_id,
    v_merchant_id,
    ARRAY[mapping.form_field_key]
  )
) fv ON true;

-- Check for missing required fields
SELECT array_agg(key)
INTO v_missing_required
FROM jsonb_each(v_field_definitions)
WHERE value->>'type' = 'auto_populate'
  AND (value->>'required')::boolean = true
  AND (v_auto_values->key IS NULL OR v_auto_values->>key IS NULL);

-- ERROR if missing required auto field
IF v_missing_required IS NOT NULL THEN
  RETURN jsonb_build_object(
    'success', false,
    'title', 'Incomplete user profile',
    'description', 'Please complete your profile first. Missing fields: ...',
    'data', jsonb_build_object(
      'missing_fields', v_missing_required,
      'action_required', 'complete_profile'
    )
  );
END IF;

-- Create upload with auto-populated values
INSERT INTO activity_upload_ledger (field_values, ...)
VALUES (v_auto_values, ...);
```

**Response Examples:**

**Success (with auto-populated values):**
```json
{
  "success": true,
  "title": "Activity uploaded successfully",
  "description": "Your submission is pending admin approval",
  "data": {
    "upload_id": "abc123-uuid",
    "activity_name": "Exercise Activity",
    "status": "pending",
    "auto_populated_fields": {
      "user_tier": "Gold Member",
      "user_outlet": "Central Branch"
    }
  }
}
```

**Error (missing required profile field):**
```json
{
  "success": false,
  "title": "Incomplete user profile",
  "description": "Please complete your profile first. Missing fields: User Tier, User Branch",
  "data": {
    "missing_fields": ["user_tier", "user_outlet"],
    "action_required": "complete_profile"
  }
}
```

---

### Modified Function: `bff_approve_activity_upload()`

**Key Changes:**
1. Get existing auto-populated values from upload record
2. Merge admin-entered values with auto values
3. Use merged values for validation and currency calculation
4. Store merged values in database

**Value Merging Logic:**
```sql
-- Get existing auto-populated values
SELECT field_values INTO v_existing_values
FROM activity_upload_ledger
WHERE id = p_upload_id;

-- MERGE using JSONB || operator
-- Admin values override auto values if same key
v_final_values := COALESCE(v_existing_values, '{}'::jsonb) || COALESCE(p_field_values, '{}'::jsonb);

-- Use v_final_values for:
-- 1. Field validation
-- 2. Currency calculation (matrix matching)
-- 3. Storage in database
-- 4. Wallet ledger metadata

UPDATE activity_upload_ledger
SET field_values = v_final_values, ...
WHERE id = p_upload_id;
```

**Merging Example:**
```javascript
// Existing values (auto-populated at upload):
{"user_tier": "Gold Member", "user_outlet": "Central Branch"}

// Admin values (entered at approval):
{"exercise_type": "yoga", "time_of_day": "morning"}

// Merged result (JSONB || operation):
{
  "user_tier": "Gold Member",
  "user_outlet": "Central Branch",
  "exercise_type": "yoga",
  "time_of_day": "morning"
}
```

**Edge Cases:**
- If admin provides value for auto-populated field, admin value wins (override)
- If optional auto field is NULL, remains NULL after merge
- Empty admin payload (`{}`) keeps all auto values unchanged

---

## Matrix Configuration

### Using Auto-Populated Fields in Matrix

**The existing matrix structure works seamlessly with auto-populated fields!**

No code changes needed - just configure the matrix to use auto-populated field values as primary or secondary dimensions.

### Example: Tier-Based Rewards

**Activity Configuration:**
```json
{
  "activity_code": "exercise",
  "activity_name": "Exercise Activity",
  "field_definitions": {
    "user_tier": {
      "type": "auto_populate",
      "label": "User Tier",
      "field_key": "membership_tier",
      "required": true,
      "order": 1
    },
    "exercise_type": {
      "type": "manual",
      "label": "Exercise Type",
      "options": ["yoga", "running", "swimming"],
      "required": true,
      "order": 2
    }
  },
  "primary_dimension": "user_tier"
}
```

**Currency Matrix:**
```
Exercise Type | Gold  | Silver | Bronze
--------------+-------+--------+-------
yoga          | 100pt | 60pt   | 30pt
running       | 120pt | 70pt   | 40pt
swimming      | 110pt | 65pt   | 35pt
```

**Stored in `activity_currency_config`:**
```sql
INSERT INTO activity_currency_config 
  (activity_id, primary_value, secondary_field, secondary_value, points_amount)
VALUES
  ('activity-uuid', 'Gold', 'exercise_type', 'yoga', 100),
  ('activity-uuid', 'Gold', 'exercise_type', 'running', 120),
  ('activity-uuid', 'Gold', 'exercise_type', 'swimming', 110),
  ('activity-uuid', 'Silver', 'exercise_type', 'yoga', 60),
  ('activity-uuid', 'Silver', 'exercise_type', 'running', 70),
  ('activity-uuid', 'Silver', 'exercise_type', 'swimming', 65),
  ('activity-uuid', 'Bronze', 'exercise_type', 'yoga', 30),
  ('activity-uuid', 'Bronze', 'exercise_type', 'running', 40),
  ('activity-uuid', 'Bronze', 'exercise_type', 'swimming', 35);
```

**Currency Calculation Flow:**
1. User uploads → System auto-populates: `user_tier: "Gold"`
2. Admin approves → Admin selects: `exercise_type: "yoga"`
3. System merges: `{"user_tier": "Gold", "exercise_type": "yoga"}`
4. System matches matrix: `primary_value='Gold' AND secondary_value='yoga'`
5. Awards: **100 points**

### Example: Outlet-Based Bonuses

**Activity Configuration:**
```json
{
  "field_definitions": {
    "user_outlet": {
      "type": "auto_populate",
      "field_key": "preferred_outlet",
      "required": true
    },
    "check_type": {
      "type": "manual",
      "options": ["plan_correct", "posm_check"],
      "required": true
    }
  },
  "primary_dimension": "user_outlet"
}
```

**Currency Matrix:**
```
Check Type    | Central | North | South
--------------+---------+-------+------
plan_correct  | 100pt   | 120pt | 150pt
posm_check    | 50pt    | 60pt  | 75pt
```

**Use Case:** Encourage activity participation in lower-performing outlets

---

## Frontend Integration

### 1. User Upload Flow

**Handle Profile Completion Error:**

```javascript
// User uploads activity
const result = await supabase.rpc('upload_activity_image', {
  p_activity_id: activityId,
  p_image_url: imageUrl
});

if (!result.success) {
  // Check if profile completion required
  if (result.data?.action_required === 'complete_profile') {
    // Show modal to redirect to profile page
    showDialog({
      title: result.title,
      message: result.description,
      primaryAction: {
        label: 'Complete Profile',
        onClick: () => {
          router.push('/profile/edit');
        }
      },
      secondaryAction: {
        label: 'Cancel'
      }
    });
  } else {
    // Other errors (limit exceeded, activity not found, etc.)
    showToast(result.title, result.description, 'error');
    
    // Show next available time if limit exceeded
    if (result.data?.next_available_at) {
      showNextAvailableTime(result.data.next_available_at);
    }
  }
} else {
  // Success
  showToast(result.title, result.description, 'success');
  
  // Optionally show which fields were auto-populated
  if (result.data?.auto_populated_fields) {
    console.log('Auto-populated:', result.data.auto_populated_fields);
  }
}
```

### 2. Admin Approval Flow

**Fetch Upload with Auto-Populated Values:**

```javascript
// Get pending uploads
const { data } = await supabase.rpc('bff_get_upload_for_approval', {
  p_upload_id: uploadId
});

const upload = data.data;

// upload.field_values already contains auto-populated values!
// Example: { user_tier: "Gold Member", user_outlet: "Central Branch" }

// Show auto values (read-only) in UI
displayAutoPopulatedFields(upload.field_values);

// Admin only fills manual fields
const manualFields = {
  exercise_type: 'yoga',
  time_of_day: 'morning'
};

// Submit approval
await supabase.rpc('bff_approve_activity_upload', {
  p_upload_id: uploadId,
  p_field_values: manualFields  // Backend merges with auto values
});
```

**Admin UI Template:**

```html
<div class="upload-approval-form">
  
  <!-- Section 1: Auto-Populated Fields (Read-Only) -->
  <div class="section auto-fields">
    <h3>User Profile (Auto-Populated)</h3>
    <p class="help-text">These values were automatically filled from the user's profile</p>
    
    <div class="field-group">
      <label>User Tier</label>
      <input 
        type="text" 
        :value="upload.field_values.user_tier" 
        disabled 
        class="readonly-field"
      />
    </div>
    
    <div class="field-group">
      <label>User Outlet</label>
      <input 
        type="text" 
        :value="upload.field_values.user_outlet" 
        disabled 
        class="readonly-field"
      />
    </div>
  </div>
  
  <!-- Section 2: Manual Fields (Editable by Admin) -->
  <div class="section manual-fields">
    <h3>Activity Details (Admin Entry)</h3>
    <p class="help-text">Please fill in the following details</p>
    
    <div class="field-group">
      <label>Exercise Type <span class="required">*</span></label>
      <select v-model="manualFields.exercise_type" required>
        <option value="">-- Select --</option>
        <option value="yoga">Yoga</option>
        <option value="running">Running</option>
        <option value="swimming">Swimming</option>
      </select>
    </div>
    
    <div class="field-group">
      <label>Time of Day <span class="required">*</span></label>
      <select v-model="manualFields.time_of_day" required>
        <option value="">-- Select --</option>
        <option value="morning">Morning</option>
        <option value="afternoon">Afternoon</option>
        <option value="evening">Evening</option>
      </select>
    </div>
  </div>
  
  <!-- Actions -->
  <div class="actions">
    <button @click="approve" :disabled="!isValid">Approve</button>
    <button @click="reject">Reject</button>
  </div>
  
</div>
```

**Dynamic Field Rendering:**

```javascript
// Get activity configuration
const { data } = await supabase.rpc('api_get_activity_full', {
  p_activity_id: activityId,
  p_mode: 'edit'
});

const fieldDefs = data.config.field_definitions;

// Separate auto vs manual fields
const autoFields = Object.entries(fieldDefs)
  .filter(([key, def]) => def.type === 'auto_populate')
  .sort((a, b) => a[1].order - b[1].order);

const manualFields = Object.entries(fieldDefs)
  .filter(([key, def]) => def.type === 'manual')
  .sort((a, b) => a[1].order - b[1].order);

// Render auto fields (read-only)
autoFields.forEach(([key, def]) => {
  renderReadOnlyField(key, def.label, upload.field_values[key]);
});

// Render manual fields (editable)
manualFields.forEach(([key, def]) => {
  renderEditableField(key, def.label, def.options, def.required);
});
```

---

## Complete End-to-End Example

### Scenario: Tier-Based Exercise Rewards

**Setup:**
- **Activity:** Exercise Activity
- **Fields:**
  - `user_tier` (auto from "membership_tier") - REQUIRED
  - `user_outlet` (auto from "preferred_outlet") - OPTIONAL
  - `exercise_type` (manual: yoga, running, swimming) - REQUIRED
- **Matrix:** user_tier × exercise_type
- **Primary Dimension:** user_tier

**User Profile:**
- Name: John Doe
- Membership Tier: Gold
- Preferred Outlet: Central Branch

---

### Step 1: User Uploads Activity

**Request:**
```http
POST /rest/v1/rpc/upload_activity_image
Content-Type: application/json
Authorization: Bearer {user_jwt}

{
  "p_activity_id": "abc-123-exercise",
  "p_image_url": "https://storage.supabase.co/bucket/uploads/john-yoga-20260131.jpg"
}
```

**Backend Processing:**
1. Gets user context: `user_id = john-uuid`
2. Checks frequency limits → ✅ Pass
3. Fetches activity field_definitions
4. Identifies auto fields: `user_tier`, `user_outlet`
5. Calls `fn_get_user_form_values()`:
   - Fetches from form_responses for John
   - Returns: `membership_tier = "Gold"`, `preferred_outlet = "Central Branch"`
6. Maps to activity fields: `user_tier = "Gold"`, `user_outlet = "Central Branch"`
7. Validates required fields → ✅ Both present
8. Creates upload record

**Database State:**
```sql
-- activity_upload_ledger
{
  id: "upload-456",
  merchant_id: "merchant-uuid",
  user_id: "john-uuid",
  activity_id: "abc-123-exercise",
  image_url: "https://storage.../john-yoga-20260131.jpg",
  field_values: {
    "user_tier": "Gold",
    "user_outlet": "Central Branch"
  },
  status: "pending",
  submitted_at: "2026-01-31T10:30:00Z"
}
```

**Response:**
```json
{
  "success": true,
  "title": "Activity uploaded successfully",
  "description": "Your submission is pending admin approval",
  "data": {
    "upload_id": "upload-456",
    "activity_name": "Exercise Activity",
    "status": "pending",
    "auto_populated_fields": {
      "user_tier": "Gold",
      "user_outlet": "Central Branch"
    }
  }
}
```

---

### Step 2: Admin Reviews Upload

**Request:**
```http
POST /rest/v1/rpc/bff_get_upload_for_approval
Content-Type: application/json
Authorization: Bearer {admin_jwt}

{
  "p_upload_id": "upload-456"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "upload_id": "upload-456",
    "user_id": "john-uuid",
    "user_name": "John Doe",
    "user_phone": "0812345678",
    "activity_id": "abc-123-exercise",
    "activity_name": "Exercise Activity",
    "image_url": "https://storage.../john-yoga-20260131.jpg",
    "field_values": {
      "user_tier": "Gold",
      "user_outlet": "Central Branch"
    },
    "status": "pending",
    "submitted_at": "2026-01-31T10:30:00Z"
  }
}
```

**Admin UI Display:**
```
┌─────────────────────────────────────────┐
│ User Profile (Auto-Populated)           │
├─────────────────────────────────────────┤
│ User Tier:   [Gold           ] (locked) │
│ User Outlet: [Central Branch ] (locked) │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Activity Details (Admin Entry)          │
├─────────────────────────────────────────┤
│ Exercise Type: [▼ Select ]   *          │
│                                          │
│ [Approve] [Reject]                       │
└─────────────────────────────────────────┘
```

---

### Step 3: Admin Approves

**Admin Actions:**
- Views uploaded image
- Sees auto-populated: Tier = Gold, Outlet = Central
- Selects: Exercise Type = "yoga"
- Clicks "Approve"

**Request:**
```http
POST /rest/v1/rpc/bff_approve_activity_upload
Content-Type: application/json
Authorization: Bearer {admin_jwt}

{
  "p_upload_id": "upload-456",
  "p_field_values": {
    "exercise_type": "yoga"
  }
}
```

**Backend Processing:**
1. Gets existing field_values: `{"user_tier": "Gold", "user_outlet": "Central Branch"}`
2. Merges with admin values: `{"exercise_type": "yoga"}`
3. Final values: `{"user_tier": "Gold", "user_outlet": "Central Branch", "exercise_type": "yoga"}`
4. Validates merged values → ✅ Pass
5. Calculates currency:
   - Matches: `primary_value = "Gold"` AND `secondary_value = "yoga"`
   - Finds: 100 points
6. Calls `post_wallet_transaction()` → Awards 100 points
7. Updates upload: status = approved, field_values = merged

**Database State:**
```sql
-- activity_upload_ledger
UPDATE activity_upload_ledger SET
  field_values = '{"user_tier": "Gold", "user_outlet": "Central Branch", "exercise_type": "yoga"}',
  status = 'approved',
  approved_at = '2026-01-31T14:00:00Z',
  approved_by = 'admin-uuid',
  points_awarded = 100,
  currency_processed_at = '2026-01-31T14:00:00Z'
WHERE id = 'upload-456';

-- wallet_ledger
INSERT INTO wallet_ledger VALUES (
  id: 'ledger-789',
  user_id: 'john-uuid',
  currency: 'points',
  transaction_type: 'earn',
  component: 'base',
  amount: 100,
  source_type: 'activity',
  source_id: 'upload-456',
  metadata: {
    "activity_id": "abc-123-exercise",
    "activity_name": "Exercise Activity",
    "field_values": {
      "user_tier": "Gold",
      "user_outlet": "Central Branch",
      "exercise_type": "yoga"
    },
    "matrix_match": {
      "primary_dimension": "user_tier",
      "primary_value": "Gold",
      "secondary_field": "exercise_type",
      "secondary_value": "yoga"
    },
    "approved_by": "admin-uuid",
    "approved_at": "2026-01-31T14:00:00Z",
    "image_url": "https://storage.../john-yoga-20260131.jpg"
  },
  balance_before: 500,
  balance_after: 600,
  created_at: '2026-01-31T14:00:00Z'
);
```

**Response:**
```json
{
  "success": true,
  "title": "Activity approved",
  "description": "Awarded 100 points",
  "data": {
    "upload_id": "upload-456",
    "points_awarded": 100,
    "tickets_awarded": [],
    "field_values": {
      "user_tier": "Gold",
      "user_outlet": "Central Branch",
      "exercise_type": "yoga"
    }
  }
}
```

---

## Implementation Checklist

### Phase 1: Backend Functions ✅
- [ ] Create `fn_get_user_form_values()` helper function
  - [ ] Handle text_value, array_value, object_value
  - [ ] Return NULL for missing fields
  - [ ] Test with sample user data
  
- [ ] Modify `upload_activity_image()` function
  - [ ] Extract auto_populate field definitions
  - [ ] Call `fn_get_user_form_values()` to fetch values
  - [ ] Map form values to activity field keys
  - [ ] Validate required auto fields not missing
  - [ ] Return error with `action_required: 'complete_profile'` if missing
  - [ ] Store auto values in `field_values` column
  - [ ] Include auto values in success response
  
- [ ] Modify `bff_approve_activity_upload()` function
  - [ ] Get existing field_values from upload record
  - [ ] Merge admin values with auto values using `||`
  - [ ] Use merged values for validation
  - [ ] Use merged values for currency calculation
  - [ ] Store merged values in database
  - [ ] Include merged values in wallet_ledger metadata

### Phase 2: Activity Configuration
- [ ] Update existing activities to use new field structure
  - [ ] Add `type` property to all existing fields
  - [ ] Set `type: "manual"` for existing fields
  - [ ] Test backwards compatibility
  
- [ ] Create new auto_populate field definitions
  - [ ] Identify which form fields to map
  - [ ] Add field_key mappings
  - [ ] Set required flags appropriately
  - [ ] Test field fetching
  
- [ ] Configure matrix with auto-populated values
  - [ ] Set primary_dimension to auto field (if desired)
  - [ ] Create matrix rows for auto field values
  - [ ] Test currency calculation

### Phase 3: Frontend Integration
- [ ] User Upload Flow
  - [ ] Handle `action_required: 'complete_profile'` error
  - [ ] Show modal with "Complete Profile" action
  - [ ] Redirect to profile edit page
  - [ ] Show which fields are missing
  - [ ] Test upload flow
  
- [ ] Admin Approval UI
  - [ ] Fetch activity field_definitions
  - [ ] Separate auto vs manual fields
  - [ ] Display auto fields as read-only
  - [ ] Display manual fields as editable
  - [ ] Only send manual fields in approval payload
  - [ ] Show merged values after approval
  - [ ] Test approval flow

### Phase 4: Testing & Validation
- [ ] Test Cases - User Upload
  - [ ] User with complete profile → Success
  - [ ] User missing required auto field → Error with clear message
  - [ ] User missing optional auto field → Success (field NULL)
  - [ ] User without form_submission → Error
  - [ ] Auto field with array_value → Correctly stored
  
- [ ] Test Cases - Admin Approval
  - [ ] Approval merges values correctly
  - [ ] Admin can override auto value (if needed)
  - [ ] Currency calculation uses merged values
  - [ ] Wallet ledger contains all field values
  - [ ] Audit trail is complete
  
- [ ] Test Cases - Matrix Configuration
  - [ ] Auto field as primary_dimension works
  - [ ] Auto field as secondary_field works
  - [ ] Mixed auto + manual fields work
  - [ ] Currency calculation matches correctly
  
- [ ] Edge Cases
  - [ ] Activity with only auto fields
  - [ ] Activity with only manual fields
  - [ ] Activity with no fields
  - [ ] Field_key doesn't exist in form
  - [ ] Form field has NULL value
  - [ ] User changes profile after upload

---

## Summary

### Key Features
1. **Auto-Population:** User profile data automatically fetched from USER_PROFILE form at upload time
2. **Error Handling:** Clear errors if required profile fields missing, with redirect to profile completion
3. **Value Merging:** Admin-entered values seamlessly merged with auto-populated values
4. **Matrix Integration:** Auto fields work in currency matrices for dynamic tier/outlet-based rewards
5. **Audit Trail:** Complete field_values stored in database and wallet_ledger metadata

### Technical Implementation
- New helper function: `fn_get_user_form_values()`
- Modified functions: `upload_activity_image()`, `bff_approve_activity_upload()`
- No schema changes required (uses existing JSONB field_definitions)
- Backwards compatible (existing activities work without changes)

### Business Value
- Reduce admin workload (auto-fill user context)
- Enable sophisticated reward strategies (tier-based, outlet-based)
- Ensure data accuracy (pulled from verified profile)
- Improve user experience (clear error messages, profile completion guidance)

---

*Document Version: 1.0*  
*Last Updated: January 31, 2026*  
*Feature: Activity Auto-Populated Fields*  
*Status: Implementation Ready*
