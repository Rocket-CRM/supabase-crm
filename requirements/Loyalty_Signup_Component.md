# Loyalty Signup Component — Specification

**Version:** 1.0  
**Last Updated:** March 2026  
**Project:** Supabase CRM — Distributable Frontend Component

---

## Purpose

A self-contained React component that any storefront (Next.js, BigCommerce, Shopify Hydrogen, etc.) can install and render with a single prop. The component handles the entire signup/login flow internally — auth config, LINE OAuth, phone OTP, profile form, consent collection — with no additional wiring from the host project.

---

## Installation & Usage

```bash
npm install @loyaltyst/signup
```

```tsx
import { LoyaltySignup } from '@loyaltyst/signup';

function StorePage() {
  return (
    <LoyaltySignup
      merchantCode="newcrm"
      onComplete={(user) => console.log('Signed up:', user)}
    />
  );
}
```

That's all the host project needs to write.

---

## Public API (Props)

| Prop | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `merchantCode` | `string` | **Yes** | — | Identifies the merchant. Component fetches all config from this. |
| `onComplete` | `(user: UserData) => void` | No | — | Called when signup/login is fully complete (auth + profile + consent). Receives user summary. |
| `onClose` | `() => void` | No | — | Called when user closes the modal/component. |
| `language` | `'en' \| 'th' \| 'zh' \| 'ja'` | No | Auto-detect from browser | Language for form labels, placeholders, and consent text. |
| `theme` | `ThemeConfig` | No | Built-in defaults | Override colors, border radius, fonts. |
| `mode` | `'modal' \| 'inline' \| 'fullscreen'` | No | `'modal'` | How the component renders in the page. |
| `apiBaseUrl` | `string` | No | Fetched from config | Override the Supabase URL (for staging/dev). |

### ThemeConfig

```typescript
interface ThemeConfig {
  primaryColor?: string;       // Brand gradient start — default: '#E91E63'
  secondaryColor?: string;     // Brand gradient end — default: '#9C27B0'
  backgroundColor?: string;    // Modal background — default: '#FFFFFF'
  textColor?: string;          // Body text — default: '#333333'
  borderRadius?: number;       // Corner radius in px — default: 12
  fontFamily?: string;         // Font stack — default: system fonts
}
```

### UserData (onComplete callback payload)

```typescript
interface UserData {
  id: string;
  tel: string | null;
  line_id: string | null;
  fullname: string | null;
  email: string | null;
  persona_id: string | null;
  access_token: string;
  refresh_token: string;
}
```

---

## Internal Architecture

### State Machine

The component operates as a linear state machine driven by the `next_step` value from `bff-auth-complete`:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   loading    │────▶│  auth_config │────▶│   auth_line   │
│ (fetch cfg)  │     │ (show UI)    │     │ (LINE OAuth)  │
└──────────────┘     └──────────────┘     └──────────────┘
                            │                     │
                            ▼                     ▼
                     ┌──────────────┐     ┌──────────────┐
                     │   auth_tel   │────▶│  auth_both   │
                     │ (phone+OTP)  │     │ (link accts) │
                     └──────────────┘     └──────────────┘
                            │                     │
                            ▼                     ▼
                     ┌──────────────┐     ┌──────────────┐
                     │   persona    │────▶│   profile    │
                     │ (select type)│     │ (form fields)│
                     └──────────────┘     └──────────────┘
                            │                     │
                            ▼                     ▼
                     ┌──────────────┐     ┌──────────────┐
                     │   consent    │────▶│   complete   │
                     │ (PDPA)       │     │ (callback)   │
                     └──────────────┘     └──────────────┘
```

State transitions are determined by the backend, not hardcoded:
- Backend returns `next_step` → component shows corresponding screen
- Backend returns `missing_data` → component renders dynamic form
- Component never assumes what comes next

### API Calls (All Internal)

| Step | Function Called | Purpose |
|------|---------------|---------|
| Mount | `bff_get_merchant_frontend_config(merchant_code)` | Get Supabase URL, anon key, LINE config, auth methods, theme |
| Auth screen | `bff_get_auth_config(merchant_code)` | Confirm auth methods (included in above) |
| LINE tap | `auth-line({ code, merchant_code, redirect_uri })` | Exchange LINE code for profile |
| Phone submit | `auth-send-otp({ phone, merchant_code })` | Send OTP SMS |
| OTP submit | `bff-auth-complete({ merchant_code, tel, otp_code, session_id, line_user_id? })` | Authenticate + get next_step + missing_data |
| Link method | `bff-auth-complete({ merchant_code, access_token, ... })` | Link LINE/tel to existing session |
| Form save | `bff_save_user_profile(form_data)` | Save profile + consent, set is_signup_form_complete |

### Token Management

- Access token stored in component memory (not localStorage by default)
- Passed to host via `onComplete` callback
- Host decides where to persist it
- Refresh token also returned — host can implement refresh logic

---

## Backend Requirement: New Config Endpoint

**`bff_get_merchant_frontend_config(p_merchant_code)`**

This is the only backend change needed. Returns everything the component needs to self-configure:

```json
{
  "supabase_url": "https://xxx.supabase.co",
  "supabase_anon_key": "eyJ...",
  "auth_methods": ["line", "tel"],
  "line_liff_id": "1234567890-abcdefgh",
  "merchant_name": "The Store",
  "merchant_logo_url": "https://cdn.example.com/logo.png",
  "theme": {
    "primary_color": "#E91E63",
    "secondary_color": "#9C27B0"
  }
}
```

Source tables: `merchant_master` (auth_methods, name, logo), project env (supabase URL/key), merchant config (LINE IDs, theme).

**Security:** This is a public endpoint (no JWT). The anon key and Supabase URL are designed to be public — they only grant access that RLS policies allow.

---

## Screen-by-Screen Specification

### Screen 1: Auth — LINE + Phone

**When shown:** On mount, after config is loaded.

**Layout:**
- Header: merchant logo + "Sign Up 1/4" (step counter from available steps)
- LINE section: If user connected via LINE, show profile picture + name + "Connected" badge
- Phone field: labeled input with country prefix
- OTP field: appears after phone submitted, 6-digit input
- Promo banner: optional, from merchant config
- Points incentive: "Sign up now get 10 Points Free!" (from merchant config)
- Next button: enabled when required auth methods are satisfied

**Behavior by auth_methods config:**

| Config | What shows |
|--------|------------|
| `["line"]` | LINE button only → on success, call bff-auth-complete → follow next_step |
| `["tel"]` | Phone + OTP only → on OTP verified, call bff-auth-complete → follow next_step |
| `["line", "tel"]` | Both → LINE first (or phone first), then prompt for second method → call bff-auth-complete with both |

**Error states:**
- "Invalid or expired OTP" → show inline error, allow resend
- "Credentials belong to different accounts" → show error message explaining the conflict
- Network error → show retry option

---

### Screen 2: Persona Selection

**When shown:** `next_step` = `complete_profile_new` or `complete_profile_existing`, AND `missing_data.persona` exists with `persona_groups` that have items.

**Layout:**
- Header: merchant logo + "Sign Up 2/4"
- Title: "Please Select Member Type"
- Persona cards: circular image + label, checkmark on selected
- Next button: enabled when `selected_persona_id` is set

**Data source:** `missing_data.persona.persona_groups[].personas[]`

Each persona object:
```json
{
  "id": "uuid",
  "name": "General customers",
  "image_url": "https://...",
  "description": "...",
  "sort_order": 1
}
```

---

### Screen 3: Profile Form

**When shown:** After persona (or directly if no persona config), when `missing_data.default_fields_config` or `missing_data.custom_fields_config` has fields.

**Layout:**
- Header: merchant logo + "Sign Up 3/4"
- Dynamic field list rendered from config
- Required fields marked with `*`
- Terms checkbox at bottom
- Next button: enabled when all required fields filled

**Field rendering by type:**

| `field_type` | Renders as |
|-------------|------------|
| `text` | Text input |
| `email` | Email input with validation |
| `tel` | Phone input (pre-filled if known) |
| `select` | Dropdown/bottom sheet with options from `field_options` |
| `date` | Date picker |
| `radio` | Radio button group |
| `checkbox` | Checkbox group |
| `textarea` | Multi-line text |

**Data source:** `missing_data.default_fields_config[].fields[]` + `missing_data.custom_fields_config[].fields[]`

Each field object:
```json
{
  "field_key": "gender",
  "label": "Gender",
  "placeholder": "Select",
  "field_type": "select",
  "is_required": true,
  "value": null,
  "field_options": [
    { "value": "male", "label": "Male" },
    { "value": "female", "label": "Female" },
    { "value": "other", "label": "Other" }
  ],
  "sort_order": 3
}
```

---

### Screen 4: Consent (PDPA)

**When shown:** After profile fields, when `missing_data.pdpa` has items.

**Layout:**
- Header: merchant logo + "Sign Up 4/4"
- Title: "แบบฟอร์มการให้ความยินยอม" + version label
- Consent body text (scrollable)
- Decline / Accept buttons at bottom

**Behavior by `interaction_type`:**

| Type | UI | User action |
|------|-----|------------|
| `notice` | Info text, no checkbox | Auto-acknowledged on view |
| `text_content` | Text + single accept checkbox | Must check to proceed |
| `checkbox_options` | Master checkbox + individual option checkboxes | Must accept mandatory ones |

**Data source:** `missing_data.pdpa[]`

---

## Scenarios Handled by Component

| # | Scenario | Component behavior |
|---|----------|-------------------|
| 1 | New user, LINE+TEL | LINE OAuth → Phone OTP → bff-auth-complete → Persona → Profile → Consent → Complete |
| 2 | New user, TEL only | Phone OTP → bff-auth-complete → Profile → Consent → Complete |
| 3 | New user, LINE only | LINE OAuth → bff-auth-complete → Profile → Consent → Complete |
| 4 | Returning user, profile complete | Auth → bff-auth-complete returns `complete` → onComplete callback immediately |
| 5 | Returning user, missing fields | Auth → bff-auth-complete returns `complete_profile_existing` → show only missing fields → Complete |
| 6 | Existing user (tel), merchant added LINE | Phone OTP → bff-auth-complete returns `verify_line` → LINE OAuth → bff-auth-complete → Complete |
| 7 | Existing user (LINE), merchant added tel | LINE OAuth → bff-auth-complete returns `verify_tel` → Phone OTP → bff-auth-complete → Complete |
| 8 | LINE and tel belong to different users | bff-auth-complete returns error → show error message → allow retry |

All routing is driven by `next_step` from the backend — the component doesn't hardcode scenario logic.

---

## Testing Strategy

### Storybook (Visual Testing — No Dev Skills Needed)

Open a URL in your browser. See every screen in every state:

- **Auth Screen:** LINE only, Tel only, LINE+Tel, LINE connected state, OTP input state, error states
- **Persona Screen:** 2 personas, 3 personas, 5 personas, with/without images
- **Profile Screen:** Few fields, many fields, with selects/dates, validation errors
- **Consent Screen:** Notice type, checkbox type, mixed, long text scroll
- **Full Flow:** Click through the entire flow with mock data
- **Themes:** Light, dark, custom brand colors

### Demo App (Real E2E Testing)

A deployed URL that connects to your real Supabase backend. Test:
- Real LINE login
- Real OTP via SMS
- Real form data from your merchant config
- Real consent versions

---

## File Structure

```
loyalty-signup/
├── package.json
├── tsup.config.ts
├── tsconfig.json
├── src/
│   ├── index.tsx                    # Public exports
│   ├── LoyaltySignup.tsx            # Main component (modal wrapper + state machine)
│   ├── types.ts                     # All TypeScript interfaces
│   ├── constants.ts                 # Default theme, timeouts, etc.
│   ├── api/
│   │   ├── client.ts                # Supabase client factory
│   │   └── auth.ts                  # All API call functions
│   ├── hooks/
│   │   ├── useSignupFlow.ts         # State machine (the brain)
│   │   ├── useConfig.ts             # Fetch + cache merchant config
│   │   └── useFormValidation.ts     # Per-section validation
│   ├── screens/
│   │   ├── LoadingScreen.tsx         # Initial config fetch
│   │   ├── AuthScreen.tsx            # LINE + Phone + OTP
│   │   ├── PersonaScreen.tsx         # Member type selection
│   │   ├── ProfileScreen.tsx         # Dynamic form fields
│   │   ├── ConsentScreen.tsx         # PDPA consent
│   │   └── CompleteScreen.tsx        # Success / transition
│   ├── components/
│   │   ├── Modal.tsx                 # Modal wrapper
│   │   ├── StepHeader.tsx            # "Sign Up 2/4" header
│   │   ├── Button.tsx                # Gradient button
│   │   ├── TextField.tsx             # Input with label
│   │   ├── SelectField.tsx           # Dropdown/bottom sheet
│   │   ├── DateField.tsx             # Date picker
│   │   ├── PersonaCard.tsx           # Circular image + label
│   │   └── ConsentSection.tsx        # Expandable consent block
│   └── styles/
│       └── theme.ts                  # CSS variable generation from ThemeConfig
├── stories/
│   ├── LoyaltySignup.stories.tsx     # Full component stories
│   ├── AuthScreen.stories.tsx        # Auth screen variations
│   ├── PersonaScreen.stories.tsx     # Persona screen variations
│   ├── ProfileScreen.stories.tsx     # Profile screen variations
│   ├── ConsentScreen.stories.tsx     # Consent screen variations
│   └── mocks/
│       ├── config.ts                 # Mock merchant config
│       ├── authResponses.ts          # Mock bff-auth-complete responses
│       └── formTemplates.ts          # Mock missing_data payloads
├── demo/
│   ├── package.json
│   ├── next.config.js
│   └── app/
│       └── page.tsx                  # <LoyaltySignup merchantCode="newcrm" />
└── .storybook/
    ├── main.ts
    └── preview.ts
```
