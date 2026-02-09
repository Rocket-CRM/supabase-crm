# Display Settings - Persona-Specific Configuration

## Overview

Display settings can now be filtered by persona, allowing each persona to see customized page layouts. This is implemented at the **block level** with persona filtering handled in the backend.

---

## Architecture

### Database Schema

```sql
display_settings
├── id
├── merchant_id
├── block_type
├── block_style
├── page
├── order
├── config (JSONB)
├── persona_ids (UUID[])  ← NEW FIELD
├── active_status
├── created_at
└── updated_at
```

**`persona_ids` Field:**
- `NULL` or `[]` = Show to all users (default behavior)
- `[uuid, ...]` = Show only to users with matching `persona_id`

---

## API Functions

### Overview of Functions

**User-Facing (Persona-Filtered):**
- `bff_get_display_blocks_cached` - **Recommended** - Cached, optimized for production
- `api_get_display_blocks_cached` - External API with merchant_code support
- `bff_get_display_settings` - Basic version without caching

**Admin (Unfiltered):**
- `admin_get_display_blocks` - With enriched config and ui_config
- `admin_get_display_settings` - Simple format
- `admin_create_display_block` - Create new block
- `admin_update_display_block` - Update existing block

**Menu/Templates:**
- `get_display_settings_menu` - Available block types (no persona relevance)

---

### 1. Get Display Blocks Cached (User-Facing) - **RECOMMENDED**

**Function:** `bff_get_display_blocks_cached(p_page, p_language)`

Primary user-facing function with persona filtering and caching. Use this for production.

```javascript
// Frontend call - user sees only their persona's blocks
const { data, error } = await supabase.rpc('bff_get_display_blocks_cached', {
  p_page: 'homepage',
  p_language: 'en'
});

// Response includes cache_hit indicator
console.log(data.cache_hit);  // true/false
console.log(data.data);  // Array of blocks
```

**Important:** Cache keys are **persona-specific**, so each persona gets their own cached version.

---

### 2. Get Display Settings (User-Facing - Basic)

**Function:** `bff_get_display_settings(p_page, p_language_code)`

Basic version without caching. Automatically filters blocks based on current user's persona.

```javascript
// Frontend call - user sees only their persona's blocks
const { data, error } = await supabase.rpc('bff_get_display_settings', {
  p_page: 'homepage',
  p_language_code: 'en'
});

// Returns only blocks where:
// - persona_ids IS NULL (shared blocks)
// - OR user's persona_id is in the persona_ids array
```

**Response:**
```json
[
  {
    "id": "uuid",
    "block_type": "banner",
    "block_style": "hero_full",
    "page": "homepage",
    "order": 1,
    "config": { /* JSONB config */ },
    "persona_ids": ["corporate-uuid"],
    "translations": {
      "header_text": "Welcome Corporate User",
      "description_text": "Enterprise Solutions"
    }
  },
  {
    "id": "uuid",
    "block_type": "navigation",
    "block_style": "horizontal",
    "page": "homepage",
    "order": 2,
    "config": { /* JSONB config */ },
    "persona_ids": null,  // Shared block - everyone sees this
    "translations": { /* ... */ }
  }
]
```

---

### 3. Get Display Blocks (Admin - Enriched) - **RECOMMENDED FOR ADMIN**

**Function:** `admin_get_display_blocks(p_page)`

Returns all blocks with enriched config and ui_config. Includes `persona_ids` field.

```javascript
// Admin panel - get blocks with full config enrichment
const { data, error } = await supabase.rpc('admin_get_display_blocks', {
  p_page: 'homepage'
});

// Returns JSON with enriched data
console.log(data);  // Array of blocks with ui_config
```

**Response includes:**
- All blocks (no persona filtering)
- `persona_ids` field for each block
- Enriched config with entity lookups
- Derived `ui_config` for frontend rendering
- Image fields transformed to arrays

---

### 4. Get All Display Settings (Admin - Simple)

**Function:** `admin_get_display_settings(p_page)`

Returns **all blocks** without persona filtering in simple table format.

```javascript
// Admin panel - simple format
const { data, error } = await supabase.rpc('admin_get_display_settings', {
  p_page: 'homepage'  // Optional - null returns all pages
});
```

---

### 5. Create Display Block (Admin)

**Function:** `admin_create_display_block(...)`

```javascript
// Create block for specific personas
const { data: blockId, error } = await supabase.rpc('admin_create_display_block', {
  p_block_type: 'banner',
  p_block_style: 'hero_full',
  p_page: 'homepage',
  p_order: 1,
  p_config: {
    "image": "corporate-hero.jpg",
    "header_text": "Enterprise Solutions"
  },
  p_persona_ids: ['corporate-uuid', 'enterprise-uuid']  // Only these personas
});

// Create shared block (all personas)
const { data: sharedBlockId } = await supabase.rpc('admin_create_display_block', {
  p_block_type: 'navigation',
  p_block_style: 'horizontal',
  p_page: 'homepage',
  p_order: 2,
  p_config: { /* ... */ },
  p_persona_ids: null  // or [] - shows to everyone
});
```

---

### 6. Update Display Block (Admin)

**Function:** `admin_update_display_block(...)`

```javascript
// Update persona assignment
const { data: success } = await supabase.rpc('admin_update_display_block', {
  p_block_id: 'block-uuid',
  p_persona_ids: ['student-uuid', 'youth-uuid']  // Reassign to different personas
});

// Update only config (persona_ids unchanged)
const { data: success } = await supabase.rpc('admin_update_display_block', {
  p_block_id: 'block-uuid',
  p_config: { /* new config */ }
  // persona_ids not provided = no change
});
```

---

## Use Cases

### Scenario 1: Different Homepage Banners

**Corporate Users:**
```javascript
// Create corporate banner
await supabase.rpc('admin_create_display_block', {
  p_block_type: 'banner',
  p_page: 'homepage',
  p_order: 1,
  p_config: {
    "image": "corporate-banner.jpg",
    "header_text": "Enterprise Solutions",
    "button_text": "Contact Sales"
  },
  p_persona_ids: ['corporate-uuid']
});
```

**Student Users:**
```javascript
// Create student banner (same order, different persona)
await supabase.rpc('admin_create_display_block', {
  p_block_type: 'banner',
  p_page: 'homepage',
  p_order: 1,
  p_config: {
    "image": "student-promo.jpg",
    "header_text": "Student Discount 20%",
    "button_text": "Shop Now"
  },
  p_persona_ids: ['student-uuid']
});
```

**Result:**
- Corporate users see corporate banner
- Student users see student banner
- Both at order position 1 (no conflict - different personas)

---

### Scenario 2: Shared + Persona-Specific Blocks

```javascript
// Navigation - shared (all users)
await supabase.rpc('admin_create_display_block', {
  p_block_type: 'navigation',
  p_page: 'homepage',
  p_order: 1,
  p_config: { /* ... */ },
  p_persona_ids: null  // Everyone sees this
});

// Featured rewards - VIP only
await supabase.rpc('admin_create_display_block', {
  p_block_type: 'featured_rewards',
  p_page: 'homepage',
  p_order: 2,
  p_config: { /* ... */ },
  p_persona_ids: ['vip-uuid', 'platinum-uuid']  // VIP only
});

// Points summary - shared
await supabase.rpc('admin_create_display_block', {
  p_block_type: 'points_summary',
  p_page: 'homepage',
  p_order: 3,
  p_config: { /* ... */ },
  p_persona_ids: null  // Everyone sees this
});
```

**Result:**
- Regular users: Navigation + Points Summary
- VIP users: Navigation + Featured Rewards + Points Summary

---

## Admin UI Workflow

### 1. Block Management View

Group blocks by persona for easier management:

```javascript
// Fetch all blocks
const { data: allBlocks } = await supabase.rpc('admin_get_display_settings', {
  p_page: 'homepage'
});

// Group by persona in UI
const corporateBlocks = allBlocks.filter(b => 
  b.persona_ids?.includes(corporatePersonaId)
);

const studentBlocks = allBlocks.filter(b => 
  b.persona_ids?.includes(studentPersonaId)
);

const sharedBlocks = allBlocks.filter(b => 
  !b.persona_ids || b.persona_ids.length === 0
);

// Display as:
// - Corporate Homepage (3 blocks)
// - Student Homepage (2 blocks)  
// - Shared Blocks (4 blocks)
```

---

### 2. Duplicate for Persona

Copy existing blocks for a different persona:

```javascript
async function duplicateBlockForPersona(sourceBlockId, targetPersonaId) {
  // Get source block
  const { data: blocks } = await supabase.rpc('admin_get_display_settings');
  const sourceBlock = blocks.find(b => b.id === sourceBlockId);
  
  // Create duplicate with new persona
  return await supabase.rpc('admin_create_display_block', {
    p_block_type: sourceBlock.block_type,
    p_block_style: sourceBlock.block_style,
    p_page: sourceBlock.page,
    p_order: sourceBlock.order,
    p_config: sourceBlock.config,
    p_persona_ids: [targetPersonaId]  // New persona
  });
}

// Usage
await duplicateBlockForPersona('corporate-banner-uuid', 'student-persona-uuid');
```

---

### 3. Bulk Operations

Duplicate entire persona "version":

```javascript
async function duplicatePersonaHomepage(fromPersonaId, toPersonaId) {
  const { data: allBlocks } = await supabase.rpc('admin_get_display_settings', {
    p_page: 'homepage'
  });
  
  // Find all blocks for source persona
  const sourceBlocks = allBlocks.filter(b => 
    b.persona_ids?.includes(fromPersonaId)
  );
  
  // Create duplicates for target persona
  for (const block of sourceBlocks) {
    await supabase.rpc('admin_create_display_block', {
      p_block_type: block.block_type,
      p_block_style: block.block_style,
      p_page: block.page,
      p_order: block.order,
      p_config: block.config,
      p_persona_ids: [toPersonaId]
    });
  }
}

// Duplicate corporate homepage for students
await duplicatePersonaHomepage('corporate-uuid', 'student-uuid');
```

---

## Frontend Implementation

### User-Facing App

```javascript
// Simple - just call and render
async function loadHomepage() {
  const { data: blocks, error } = await supabase.rpc('bff_get_display_settings', {
    p_page: 'homepage',
    p_language_code: currentLanguage
  });
  
  if (error) throw error;
  
  // Blocks are already filtered by user's persona
  // Just render in order
  return blocks.sort((a, b) => a.order - b.order);
}
```

---

### Admin Panel

```javascript
// Show blocks grouped by persona
function DisplaySettingsManager({ page }) {
  const [blocks, setBlocks] = useState([]);
  const [personas, setPersonas] = useState([]);
  
  useEffect(() => {
    loadData();
  }, [page]);
  
  async function loadData() {
    // Get all blocks (unfiltered)
    const { data: allBlocks } = await supabase.rpc('admin_get_display_settings', {
      p_page: page
    });
    
    // Get personas
    const { data: personaList } = await supabase
      .from('persona_master')
      .select('*');
    
    setBlocks(allBlocks);
    setPersonas(personaList);
  }
  
  // Group blocks by persona
  const groupedBlocks = personas.reduce((acc, persona) => {
    acc[persona.id] = blocks.filter(b => 
      b.persona_ids?.includes(persona.id)
    );
    return acc;
  }, {});
  
  // Shared blocks
  groupedBlocks['shared'] = blocks.filter(b => 
    !b.persona_ids || b.persona_ids.length === 0
  );
  
  return (
    <div>
      {Object.entries(groupedBlocks).map(([personaId, blocks]) => (
        <PersonaBlockGroup 
          key={personaId}
          persona={personaId === 'shared' ? null : personas.find(p => p.id === personaId)}
          blocks={blocks}
        />
      ))}
    </div>
  );
}
```

---

## Migration

Existing blocks automatically show to all personas (persona_ids defaults to NULL).

```sql
-- All existing blocks already have persona_ids = NULL
-- This means they show to everyone by default
-- No data migration needed!

-- If you want to explicitly see which blocks are shared:
SELECT id, block_type, page, persona_ids 
FROM display_settings 
WHERE persona_ids IS NULL OR persona_ids = '{}';
```

---

## Best Practices

1. **Shared Blocks First:** Create common blocks (navigation, footer) with `persona_ids = NULL`

2. **Persona-Specific Content:** Only assign personas to truly different content (banners, featured items)

3. **Consistent Ordering:** Use same `order` values for persona-specific variants of same block type

4. **Admin UX:** Group blocks by persona in admin UI for clarity

5. **Translations:** All blocks use same translation system (translations table) regardless of persona

6. **Validation:** Warn admins if same block type + order + page exists for overlapping personas

---

## Database Query Examples

### Find blocks for specific persona:
```sql
SELECT * FROM display_settings 
WHERE page = 'homepage' 
  AND (persona_ids @> ARRAY['corporate-uuid']::uuid[] OR persona_ids IS NULL);
```

### Find shared blocks:
```sql
SELECT * FROM display_settings 
WHERE persona_ids IS NULL OR persona_ids = '{}';
```

### Find blocks assigned to multiple personas:
```sql
SELECT * FROM display_settings 
WHERE array_length(persona_ids, 1) > 1;
```

---

*Updated: January 21, 2026*

