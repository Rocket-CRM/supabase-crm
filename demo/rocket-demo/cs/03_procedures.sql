-- Rocket Demo CS AOPs (Agent Operating Procedures)
-- Merchant: fae172a5-de90-440e-a766-db6a5982cc9b
-- Booking confirmation uses create_ticket as durable write until clinic booking stubs exist.

DO $$
DECLARE
  v_mid uuid := 'fae172a5-de90-440e-a766-db6a5982cc9b';
BEGIN
  DELETE FROM cs_procedures
  WHERE merchant_id = v_mid
    AND trigger_intent IN (
      'product_inquiry', 'appointment_booking', 'order_tracking',
      'place_order', 'medical_advice'
    );

  -- 1) Knowledge Reply Handler
  INSERT INTO cs_procedures (
    merchant_id, name, description, trigger_intent, flexibility,
    raw_content, compiled_steps, config, guardrails, is_active, version
  ) VALUES (
    v_mid,
    'Knowledge Reply Handler',
    'Ground product/clinic FAQ answers in Rocket Demo knowledge base',
    'product_inquiry',
    'guided',
    $raw$
AOP Name: Knowledge Reply Handler
Trigger Intent: product_inquiry
Flexibility: Guided

1. Step "Understand Question": Identify if question is product formula, routine, promo, clinic policy, or medical.
   - If medical diagnosis/prescription/lab: hand off — do not answer. (Intent should be medical_advice.)
2. Step "Search Knowledge": Use knowledge prefetch for the topic. Prefer custom answers when patterns match.
3. Step "Reply Grounded": Answer only from retrieved knowledge. Cite product/package names. Offer related help (booking, order, promo).
4. Step "Close or Continue": Ask if they need anything else. No write tools.
$raw$,
    jsonb_build_object(
      'steps', jsonb_build_array(
        jsonb_build_object(
          'index', 1,
          'name', 'Understand Question',
          'step_topic', 'Classify FAQ vs medical boundary',
          'tools', '[]'::jsonb,
          'variables_out', jsonb_build_array('topic', 'is_medical'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'skip_condition', 'all variables_out already collected'
        ),
        jsonb_build_object(
          'index', 2,
          'name', 'Search Knowledge',
          'step_topic', 'Prefetch knowledge for product/clinic/promo FAQs',
          'tools', '[]'::jsonb,
          'data_needs', jsonb_build_array(
            jsonb_build_object(
              'source', 'knowledge',
              'query_hints', jsonb_build_array('product formula', 'clinic package', 'promotion', 'routine', 'shipping'),
              'when', 'always'
            )
          ),
          'action_tools', '[]'::jsonb,
          'next', 3
        ),
        jsonb_build_object(
          'index', 3,
          'name', 'Reply Grounded',
          'step_topic', 'Answer from knowledge only; no clinical claims',
          'tools', '[]'::jsonb,
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'next', 4
        ),
        jsonb_build_object(
          'index', 4,
          'name', 'Close or Continue',
          'step_topic', 'Offer next help without write actions',
          'tools', '[]'::jsonb,
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb
        )
      ),
      'entity_extractors', jsonb_build_array(
        jsonb_build_object('variable', 'product_keyword', 'type', 'keyword',
          'keywords', jsonb_build_array('niacinamide', 'retinol', 'serum', 'cleanser', 'spf', 'riceglow', 'glowlab', 'agesoft')),
        jsonb_build_object('variable', 'intent_keyword', 'type', 'keyword',
          'keywords', jsonb_build_array('promo', 'ส่วนลด', 'package', 'แพ็กเกจ', 'how to use', 'ใช้ยังไง'))
      ),
      'default_data_needs', jsonb_build_object(
        'no_entities', jsonb_build_array(
          jsonb_build_object('source', 'knowledge', 'query_hints', jsonb_build_array('rocket club', 'faq'))
        )
      )
    ),
    jsonb_build_object('tone_override', 'friendly_expert', 'max_turns', 8),
    jsonb_build_object('rules', jsonb_build_array('Never invent medical advice', 'Stay within retrieved knowledge')),
    true,
    1
  );

  -- 2) Clinic Package Booking
  INSERT INTO cs_procedures (
    merchant_id, name, description, trigger_intent, flexibility,
    raw_content, compiled_steps, config, guardrails, is_active, version
  ) VALUES (
    v_mid,
    'Clinic Package Booking',
    'Propose clinic packages, collect time, confirm, create booking ticket',
    'appointment_booking',
    'guided',
    $raw$
AOP Name: Clinic Package Booking
Trigger Intent: appointment_booking
Flexibility: Guided (agentic when proposing packages)

1. Step "Capture Intent": Ask what concern or package interest (analysis, laser, checkup). Collect name/phone if missing.
2. Step "Propose Packages": Prefetch clinic package knowledge. Propose 1–2 packages with price/duration. Ask which one.
3. Step "Collect Time": Ask preferred date/time window and branch (Siam Paragon / EmQuartier). Hours Tue–Sun 10:00–20:00.
4. Step "Confirm": Repeat package + slot + branch. Get explicit yes.
5. Step "Create Booking": Use @Create Ticket with type clinic_booking, summary including package, slot, branch, contact. Tell customer booking ref from ticket id (prefix BK-RKT-).
6. Step "Send Confirmation": Summarize confirmation. Offer calendar tip (arrive 15 min early).
7. Step "Escalate": If unavailable/unclear after 2 tries, @Create Ticket for human clinic coordinator.
$raw$,
    jsonb_build_object(
      'steps', jsonb_build_array(
        jsonb_build_object(
          'index', 1,
          'name', 'Capture Intent',
          'step_topic', 'Collect booking interest and contact basics',
          'tools', '[]'::jsonb,
          'variables_out', jsonb_build_array('concern', 'customer_name', 'phone'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb
        ),
        jsonb_build_object(
          'index', 2,
          'name', 'Propose Packages',
          'step_topic', 'Propose clinic packages from knowledge inventory',
          'flexibility', 'agentic',
          'tools', '[]'::jsonb,
          'variables_out', jsonb_build_array('package_name', 'package_price'),
          'data_needs', jsonb_build_array(
            jsonb_build_object(
              'source', 'knowledge',
              'query_hints', jsonb_build_array('clinic package', 'Skin Analysis', 'Glow Laser', 'Wellness Skin Checkup', 'แพ็กเกจคลินิก'),
              'when', 'always'
            )
          ),
          'action_tools', '[]'::jsonb,
          'next', 3
        ),
        jsonb_build_object(
          'index', 3,
          'name', 'Collect Time',
          'step_topic', 'Collect preferred slot and branch',
          'required_variables', jsonb_build_array('package_name'),
          'variables_out', jsonb_build_array('slot', 'branch'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'next', 4
        ),
        jsonb_build_object(
          'index', 4,
          'name', 'Confirm',
          'step_topic', 'Confirm package and time with customer',
          'required_variables', jsonb_build_array('package_name', 'slot', 'branch'),
          'variables_out', jsonb_build_array('confirmed'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'next', 5
        ),
        jsonb_build_object(
          'index', 5,
          'name', 'Create Booking',
          'step_topic', 'Create clinic_booking ticket as booking write',
          'tools', jsonb_build_array('Create Ticket'),
          'action_tools', jsonb_build_array(
            jsonb_build_object(
              'tool', 'create_ticket',
              'args_from', jsonb_build_object(
                'type', 'clinic_booking',
                'package_name', 'package_name',
                'slot', 'slot',
                'branch', 'branch'
              ),
              'requires_confirmation', true
            )
          ),
          'data_needs', '[]'::jsonb,
          'next', 6
        ),
        jsonb_build_object(
          'index', 6,
          'name', 'Send Confirmation',
          'step_topic', 'Send booking confirmation summary',
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb
        ),
        jsonb_build_object(
          'index', 7,
          'name', 'Escalate',
          'step_topic', 'Escalate unclear booking to human',
          'tools', jsonb_build_array('Create Ticket'),
          'action_tools', jsonb_build_array(
            jsonb_build_object('tool', 'create_ticket', 'requires_confirmation', false)
          ),
          'data_needs', '[]'::jsonb
        )
      ),
      'entity_extractors', jsonb_build_array(
        jsonb_build_object('variable', 'package_keyword', 'type', 'keyword',
          'keywords', jsonb_build_array('laser', 'skin analysis', 'checkup', 'เลเซอร์', 'วิเคราะห์ผิว', 'นัดหมาย', 'จองคิว')),
        jsonb_build_object('variable', 'branch', 'type', 'keyword',
          'keywords', jsonb_build_array('siam', 'paragon', 'emquartier', 'สยาม', 'เอ็มควอเทียร์'))
      ),
      'default_data_needs', jsonb_build_object(
        'no_entities', jsonb_build_array(
          jsonb_build_object('source', 'knowledge', 'query_hints', jsonb_build_array('clinic package menu'))
        )
      )
    ),
    jsonb_build_object('tone_override', 'warm_clinic', 'max_turns', 12),
    jsonb_build_object('rules', jsonb_build_array('No medical diagnosis during booking', 'Confirm before create_ticket')),
    true,
    1
  );

  -- 3) Order Tracking
  INSERT INTO cs_procedures (
    merchant_id, name, description, trigger_intent, flexibility,
    raw_content, compiled_steps, config, guardrails, is_active, version
  ) VALUES (
    v_mid,
    'Order Tracking Handler',
    'Verify order details then return shipping/tracking status',
    'order_tracking',
    'guided',
    $raw$
AOP Name: Order Tracking Handler
Trigger Intent: order_tracking
Flexibility: Guided

1. Step "Collect Order Info": Ask order number + platform if missing. LINE chat ≠ marketplace platform.
2. Step "Lookup Order": Use @Lookup Order. If not found: retry once, then escalate.
3. Step "Get Shipping": Use @Get Order Shipping for carrier, tracking number, ETA, URL.
4. Step "Reply Status": Share status clearly. Offer help if delayed.
5. Step "Escalate": @Create Ticket if lookup fails twice or mismatch on customer identity.
$raw$,
    jsonb_build_object(
      'steps', jsonb_build_array(
        jsonb_build_object(
          'index', 1,
          'name', 'Collect Order Info',
          'step_topic', 'Collect order_number and platform',
          'variables_out', jsonb_build_array('order_number', 'platform'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'skip_condition', 'order_number IS NOT NULL'
        ),
        jsonb_build_object(
          'index', 2,
          'name', 'Lookup Order',
          'step_topic', 'Prefetch order by number and platform',
          'required_variables', jsonb_build_array('order_number'),
          'tools', jsonb_build_array('Lookup Order'),
          'data_needs', jsonb_build_array(
            jsonb_build_object(
              'source', 'lookup_order',
              'args_from', jsonb_build_object('order_id', 'order_number', 'platform', 'platform'),
              'when', 'order_number IS NOT NULL'
            )
          ),
          'branches', jsonb_build_object('found', 3, 'not_found', 5),
          'action_tools', '[]'::jsonb
        ),
        jsonb_build_object(
          'index', 3,
          'name', 'Get Shipping',
          'step_topic', 'Prefetch shipping and tracking details',
          'tools', jsonb_build_array('Get Order Shipping'),
          'data_needs', jsonb_build_array(
            jsonb_build_object(
              'source', 'get_order_shipping',
              'args_from', jsonb_build_object('order_id', 'order_number', 'platform', 'platform'),
              'when', 'order_number IS NOT NULL'
            )
          ),
          'action_tools', '[]'::jsonb,
          'next', 4
        ),
        jsonb_build_object(
          'index', 4,
          'name', 'Reply Status',
          'step_topic', 'Tell customer tracking status ETA and URL',
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb
        ),
        jsonb_build_object(
          'index', 5,
          'name', 'Escalate',
          'step_topic', 'Create ticket when order cannot be verified',
          'tools', jsonb_build_array('Create Ticket'),
          'action_tools', jsonb_build_array(
            jsonb_build_object('tool', 'create_ticket', 'requires_confirmation', false)
          ),
          'data_needs', '[]'::jsonb
        )
      ),
      'entity_extractors', jsonb_build_array(
        jsonb_build_object('variable', 'order_number', 'type', 'regex', 'pattern', $p$\y(RKT-ORD-\d{4,8}|PM-?\d{4,8}|\d{6,12})\y$p$),
        jsonb_build_object('variable', 'platform', 'type', 'keyword',
          'keywords', jsonb_build_array('shopee', 'lazada', 'tiktok', 'online', 'ช้อปปี้', 'ลาซาด้า'))
      ),
      'default_data_needs', jsonb_build_object(
        'no_entities', jsonb_build_array(
          jsonb_build_object('source', 'recent_orders', 'limit', 3)
        )
      )
    ),
    jsonb_build_object('max_turns', 8),
    jsonb_build_object('rules', jsonb_build_array('Verify order before sharing PII-rich tracking details')),
    true,
    1
  );

  -- 4) Ecommerce Order Assistant
  INSERT INTO cs_procedures (
    merchant_id, name, description, trigger_intent, flexibility,
    raw_content, compiled_steps, config, guardrails, is_active, version
  ) VALUES (
    v_mid,
    'Ecommerce Order Assistant',
    'Search catalog, check promos, confirm, place order',
    'place_order',
    'guided',
    $raw$
AOP Name: Ecommerce Order Assistant
Trigger Intent: place_order
Flexibility: Guided (agentic on recommend)

1. Step "Clarify Need": repurchase, gift, or routine. If medical question appears, switch to medical boundary.
2. Step "Search Products": Use @Search Products for Rocket brands (RiceGlow, GlowLab, AgeSoft, etc.).
3. Step "Check Promotion": Use @Check Promotion. Mention current demo promos from knowledge if relevant.
4. Step "Confirm Cart": Confirm items, qty, shipping address, contact. Get explicit yes.
5. Step "Create Order": Use @Create Order. Return order number and next-step payment/shipping copy.
6. Step "Escalate": @Create Ticket if payment/address issues.
$raw$,
    jsonb_build_object(
      'steps', jsonb_build_array(
        jsonb_build_object(
          'index', 1,
          'name', 'Clarify Need',
          'step_topic', 'Clarify order intent and constraints',
          'variables_out', jsonb_build_array('order_goal', 'product_query'),
          'data_needs', jsonb_build_array(
            jsonb_build_object('source', 'knowledge', 'query_hints', jsonb_build_array('current promo', 'bestsellers'), 'when', 'always')
          ),
          'action_tools', '[]'::jsonb
        ),
        jsonb_build_object(
          'index', 2,
          'name', 'Search Products',
          'step_topic', 'Search catalog for matching SKUs',
          'flexibility', 'agentic',
          'tools', jsonb_build_array('Search Products'),
          'variables_out', jsonb_build_array('selected_items'),
          'data_needs', jsonb_build_array(
            jsonb_build_object(
              'source', 'search_products',
              'args_from', jsonb_build_object('query', 'product_query'),
              'when', 'product_query IS NOT NULL'
            )
          ),
          'action_tools', '[]'::jsonb,
          'next', 3
        ),
        jsonb_build_object(
          'index', 3,
          'name', 'Check Promotion',
          'step_topic', 'Check active promotions',
          'tools', jsonb_build_array('Check Promotion'),
          'data_needs', jsonb_build_array(
            jsonb_build_object('source', 'check_promotion', 'when', 'always'),
            jsonb_build_object('source', 'knowledge', 'query_hints', jsonb_build_array('current promo'), 'when', 'always')
          ),
          'action_tools', '[]'::jsonb,
          'next', 4
        ),
        jsonb_build_object(
          'index', 4,
          'name', 'Confirm Cart',
          'step_topic', 'Confirm items address and contact',
          'required_variables', jsonb_build_array('selected_items'),
          'variables_out', jsonb_build_array('shipping_address', 'confirmed'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'next', 5
        ),
        jsonb_build_object(
          'index', 5,
          'name', 'Create Order',
          'step_topic', 'Place order after confirmation',
          'tools', jsonb_build_array('Create Order'),
          'action_tools', jsonb_build_array(
            jsonb_build_object(
              'tool', 'create_order',
              'args_from', jsonb_build_object('items', 'selected_items', 'shipping_address', 'shipping_address'),
              'requires_confirmation', true
            )
          ),
          'data_needs', '[]'::jsonb
        ),
        jsonb_build_object(
          'index', 6,
          'name', 'Escalate',
          'step_topic', 'Ticket on order failure',
          'tools', jsonb_build_array('Create Ticket'),
          'action_tools', jsonb_build_array(
            jsonb_build_object('tool', 'create_ticket', 'requires_confirmation', false)
          ),
          'data_needs', '[]'::jsonb
        )
      ),
      'entity_extractors', jsonb_build_array(
        jsonb_build_object('variable', 'product_query', 'type', 'keyword',
          'keywords', jsonb_build_array('serum', 'retinol', 'cleanser', 'niacinamide', 'สั่งซื้อ', 'order', 'ซื้อ'))
      ),
      'default_data_needs', jsonb_build_object(
        'no_entities', jsonb_build_array(
          jsonb_build_object('source', 'knowledge', 'query_hints', jsonb_build_array('bestsellers'))
        )
      )
    ),
    jsonb_build_object('max_turns', 14),
    jsonb_build_object('rules', jsonb_build_array('No clinical claims in product pitch', 'Confirm before create_order')),
    true,
    1
  );

  -- 5) Medical Specialist Route
  INSERT INTO cs_procedures (
    merchant_id, name, description, trigger_intent, flexibility,
    raw_content, compiled_steps, config, guardrails, is_active, version
  ) VALUES (
    v_mid,
    'Medical Specialist Route',
    'Strict refuse clinical advice; route to specialist or clinic booking',
    'medical_advice',
    'strict',
    $raw$
AOP Name: Medical Specialist Route
Trigger Intent: medical_advice
Flexibility: Strict

1. Step "Refuse Clinical Advice": Clearly state you cannot diagnose, prescribe, dose, or interpret labs. Do NOT provide workarounds that are still medical advice.
2. Step "Offer Path": Offer (A) Rocket Clinic booking (appointment_booking) or (B) specialist human ticket.
3. Step "Create Specialist Ticket": If customer chooses specialist or is distressed, @Create Ticket type specialist_medical with short summary of question (no invented diagnosis).
4. Step "Close Safely": Confirm next step. If emergency symptoms described, advise seeking emergency care — do not triage.
$raw$,
    jsonb_build_object(
      'steps', jsonb_build_array(
        jsonb_build_object(
          'index', 1,
          'name', 'Refuse Clinical Advice',
          'step_topic', 'Hard refuse diagnosis prescription lab interpretation',
          'priority', 'empathy_first',
          'data_needs', jsonb_build_array(
            jsonb_build_object(
              'source', 'knowledge',
              'query_hints', jsonb_build_array('medical boundary', 'what AI must not answer', 'pregnancy'),
              'when', 'always'
            )
          ),
          'action_tools', '[]'::jsonb,
          'next', 2
        ),
        jsonb_build_object(
          'index', 2,
          'name', 'Offer Path',
          'step_topic', 'Offer clinic booking or specialist ticket',
          'variables_out', jsonb_build_array('route_choice'),
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb,
          'code_conditions', jsonb_build_array(
            jsonb_build_object('condition', 'route_choice == ''booking''', 'goto', 4),
            jsonb_build_object('condition', 'route_choice == ''specialist''', 'goto', 3)
          )
        ),
        jsonb_build_object(
          'index', 3,
          'name', 'Create Specialist Ticket',
          'step_topic', 'Create specialist_medical ticket',
          'tools', jsonb_build_array('Create Ticket'),
          'action_tools', jsonb_build_array(
            jsonb_build_object(
              'tool', 'create_ticket',
              'args_from', jsonb_build_object('type', 'specialist_medical'),
              'requires_confirmation', true
            )
          ),
          'data_needs', '[]'::jsonb,
          'next', 4
        ),
        jsonb_build_object(
          'index', 4,
          'name', 'Close Safely',
          'step_topic', 'Confirm safe next step; no clinical content',
          'data_needs', '[]'::jsonb,
          'action_tools', '[]'::jsonb
        )
      ),
      'entity_extractors', jsonb_build_array(
        jsonb_build_object('variable', 'medical_keyword', 'type', 'keyword',
          'keywords', jsonb_build_array('diagnosis', 'diagnose', 'prescribe', 'ยา', 'วินิจฉัย', 'แล็บ', 'หมอ', 'pregnant', 'ตั้งครรภ์', 'dose'))
      ),
      'default_data_needs', jsonb_build_object(
        'no_entities', jsonb_build_array(
          jsonb_build_object('source', 'knowledge', 'query_hints', jsonb_build_array('medical boundary'))
        )
      )
    ),
    jsonb_build_object('max_turns', 6, 'tone_override', 'careful_clear'),
    jsonb_build_object('rules', jsonb_build_array(
      'NEVER diagnose, prescribe, dose, or interpret labs',
      'NEVER suggest a disease name',
      'Offer booking or specialist ticket only'
    )),
    true,
    1
  );

  -- Seed CS action config (ignore failures — registry tables vary by env)
  BEGIN
    PERFORM cs_fn_seed_action_config(v_mid);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'cs_fn_seed_action_config skipped: %', SQLERRM;
  END;
END $$;
