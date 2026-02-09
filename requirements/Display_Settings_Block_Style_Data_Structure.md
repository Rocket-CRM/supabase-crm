# Display Settings Block Style Data Structure

Config JSONB templates for each display block style.

---

## Profile Card

### Style 1

```json
{
  "group_1": {
    "items": [
      {
        "data_type": "",
        "typography": "",
        "order": 0
      }
    ]
  },
  "group_2": {
    "active": false,
    "object": "",
    "items": [
      {
        "entity": "",
        "custom_image": false,
        "image": "",
        "order": 0
      }
    ]
  }
}
```

### Style 2

```json
{
  "group_1": {
    "show_member_type": false,
    "show_my_qr": false,
    "items": [
      {
        "data_type": "",
        "typography": "",
        "order": 0
      }
    ]
  },
  "group_2": {
    "active": false,
    "count_object": ""
  }
}
```

---

## Navigation

### Horizontal

```json
{
  "group_1": {
    "items": [
      {
        "header_text": "",
        "image": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  },
  "group_2": {
    "items": [
      {
        "header_text": "",
        "image": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  }
}
```

### Grid

```json
{
  "group_1": {
    "items": [
      {
        "header_text": "",
        "image": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  },
  "group_2": {
    "object": "",
    "items": [
      {
        "entity": "",
        "custom_image": false,
        "image": "",
        "order": 0
      }
    ]
  }
}
```

### Cards

```json
{
  "group_1": {
    "items": [
      {
        "image": "",
        "header_text": "",
        "description_text": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  },
  "group_2": {
    "items": [
      {
        "image": "",
        "header_text": "",
        "description_text": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  }
}
```

### List

```json
{
  "group_1": {
    "items": [
      {
        "image": "",
        "header_text": "",
        "description_text": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  }
}
```

---

## Banner

### Full Width

```json
{
  "background_color": "#FFFFFF",
  "layout": "full_width",
  "height": "400px"
}
```

### Split Screen

```json
{
  "background_color": "#FFFFFF",
  "layout": "split_screen",
  "height": "300px"
}
```

### Carousel

```json
{
  "show_text": false,
  "alignment": "",
  "group_1": [
    {
      "image": "",
      "header_text": "",
      "description_text": "",
      "button_text": "",
      "link_type": "",
      "page": "",
      "url": ""
    }
  ]
}
```

### Carousel

```json
{
  "show_text": false,
  "alignment": "",
  "group_1": {
    "items": [
      {
        "image": "",
        "header_text": "",
        "description_text": "",
        "button_text": "",
        "link_type": "",
        "page": "",
        "url": "",
        "order": 0
      }
    ]
  }
}
```

---

## Notes

**Translatable fields:** header_text, description_text, button_text  
**Level 1:** Top-level in config  
**Level 2:** Inside group objects or fields  
**Level 3:** Inside array items  
**All array items include `order` field for sequencing**

---

## Persona-Specific Display Settings

Each display block can be assigned to specific personas using the `persona_ids` field:

- **`persona_ids: NULL` or `[]`** → Block shows to all users (default)
- **`persona_ids: [uuid, uuid, ...]`** → Block shows only to users with matching persona

**Examples:**

```sql
-- Block shows to all users
persona_ids: NULL

-- Block shows only to Corporate and Enterprise personas
persona_ids: ['corporate-uuid', 'enterprise-uuid']

-- Block shows only to Student persona
persona_ids: ['student-uuid']
```

**Use Cases:**
- Different homepage banners for Corporate vs Student users
- Persona-specific navigation menus
- VIP-only featured content blocks
- Role-specific quick actions

**Admin Workflow:**
- Create blocks and assign to target personas
- Use "Duplicate for Persona" to copy blocks and reassign
- Group blocks by persona in admin UI for easier management
- Shared blocks (persona_ids=NULL) appear for all users

**API Functions:**
- `bff_get_display_settings(p_page, p_language_code)` - User-facing, persona-filtered
- `admin_get_display_settings(p_page)` - Admin function, returns all blocks unfiltered
- `admin_create_display_block(...)` - Create block with persona assignment
- `admin_update_display_block(...)` - Update block including persona_ids

*Updated: January 21, 2026*
