-- USER_PROFILE custom fields (groups) + PDPA notices/consents + comm topics for Rocket Demo.
-- Idempotent: field groups keyed rkt_profile_*; consent version_codes rkt-*; topics by stable names.
CREATE OR REPLACE FUNCTION public.custom_internal_demo_bootstrap_profile_consent()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_form_id uuid;
  v_fg_about uuid;
  v_fg_skin uuid;
  v_fg_lifestyle uuid;
  v_ff uuid;
  v_notice uuid;
  v_tos uuid;
  v_marketing uuid;
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;
  v_merchant_id := (v_settings->>'merchant_id')::uuid;

  SELECT id INTO v_form_id
  FROM form_templates
  WHERE merchant_id = v_merchant_id AND code = 'USER_PROFILE'
  LIMIT 1;

  IF v_form_id IS NULL THEN
    INSERT INTO form_templates (
      merchant_id, name, description, status, code, allow_bulk_import
    ) VALUES (
      v_merchant_id,
      'Member profile',
      'Tell us about your skin and interests so Rocket Club can personalize your experience.',
      'published',
      'USER_PROFILE',
      true
    ) RETURNING id INTO v_form_id;
  ELSE
    UPDATE form_templates
    SET
      name = 'Member profile',
      description = 'Tell us about your skin and interests so Rocket Club can personalize your experience.',
      status = 'published',
      allow_bulk_import = true
    WHERE id = v_form_id;
  END IF;

  -- Remove prior Rocket Demo profile seed fields (no member answers on empty merchant profile yet).
  DELETE FROM form_responses fr
  USING form_fields ff
  WHERE fr.field_id = ff.id
    AND ff.form_id = v_form_id
    AND ff.field_key LIKE 'rkt_%';
  DELETE FROM form_field_options fo
  USING form_fields ff
  WHERE fo.field_id = ff.id AND ff.form_id = v_form_id AND ff.field_key LIKE 'rkt_%';
  DELETE FROM form_fields ff
  WHERE ff.form_id = v_form_id AND ff.field_key LIKE 'rkt_%';
  DELETE FROM form_field_groups fg
  WHERE fg.form_id = v_form_id AND fg.group_key LIKE 'rkt_profile_%';

  INSERT INTO form_field_groups (form_id, group_key, group_name, order_index)
  VALUES (v_form_id, 'rkt_profile_about', 'About you', 1)
  RETURNING id INTO v_fg_about;

  INSERT INTO form_field_groups (form_id, group_key, group_name, order_index)
  VALUES (v_form_id, 'rkt_profile_skin', 'Your skin', 2)
  RETURNING id INTO v_fg_skin;

  INSERT INTO form_field_groups (form_id, group_key, group_name, order_index)
  VALUES (v_form_id, 'rkt_profile_lifestyle', 'Lifestyle & interests', 3)
  RETURNING id INTO v_fg_lifestyle;

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_about, 'rkt_skin_type', 'What best describes your skin?', 'single_select', 1,
    true, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'normal', 'Balanced / normal', 1),
    (v_ff, 'dry', 'Dry or dehydrated', 2),
    (v_ff, 'oily', 'Oily or combination', 3),
    (v_ff, 'sensitive', 'Sensitive or reactive', 4),
    (v_ff, 'mature', 'Mature — firmness & fine lines', 5);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_about, 'rkt_age_range', 'Age range', 'single_select', 2,
    false, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, '18_24', '18–24', 1),
    (v_ff, '25_34', '25–34', 2),
    (v_ff, '35_44', '35–44', 3),
    (v_ff, '45_54', '45–54', 4),
    (v_ff, '55_plus', '55+', 5);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_skin, 'rkt_skin_concerns', 'Top skin goals (pick up to 3)', 'multi-select', 1,
    true, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'hydration', 'Deep hydration', 1),
    (v_ff, 'brightening', 'Radiance & dullness', 2),
    (v_ff, 'acne', 'Blemishes & pores', 3),
    (v_ff, 'anti_aging', 'Fine lines & firmness', 4),
    (v_ff, 'barrier', 'Barrier repair', 5),
    (v_ff, 'spf', 'Daily sun protection', 6);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_skin, 'rkt_sensitivity', 'How does your skin usually react to new products?', 'single_select', 2,
    true, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'rarely', 'Rarely irritated', 1),
    (v_ff, 'sometimes', 'Sometimes red or stingy', 2),
    (v_ff, 'often', 'Often sensitive — I patch test', 3);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_skin, 'rkt_routine_depth', 'Your skincare routine', 'single_select', 3,
    false, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'minimal', 'Minimal (cleanse + moisturize)', 1),
    (v_ff, 'essentials', 'Essentials (+ serum or SPF)', 2),
    (v_ff, 'advanced', 'Advanced (layered actives)', 3);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_lifestyle, 'rkt_shop_channels', 'Where do you usually shop for skincare?', 'multi-select', 1,
    false, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'flagship', 'Rocket Club boutique / flagship', 1),
    (v_ff, 'department', 'Department store counters', 2),
    (v_ff, 'online', 'Brand website / app', 3),
    (v_ff, 'marketplace', 'Marketplaces (Shopee, Lazada, etc.)', 4);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_lifestyle, 'rkt_interests', 'What are you into?', 'multi-select', 2,
    true, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'clean_beauty', 'Clean & conscious formulas', 1),
    (v_ff, 'kbeauty', 'K-beauty routines', 2),
    (v_ff, 'clinical', 'Clinical actives (retinol, acids)', 3),
    (v_ff, 'spa_selfcare', 'Spa-at-home & self-care', 4),
    (v_ff, 'fragrance', 'Fragrance layering with body care', 5),
    (v_ff, 'wellness', 'Wellness & inner glow', 6);

  INSERT INTO form_fields (
    form_id, group_id, field_key, label, field_type, order_index,
    is_required, merchant_id, visible_to_user, visible_to_admin
  ) VALUES (
    v_form_id, v_fg_lifestyle, 'rkt_routine_time', 'When do you enjoy your routine most?', 'single_select', 3,
    false, v_merchant_id, true, true
  ) RETURNING id INTO v_ff;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff, 'morning', 'Morning refresh', 1),
    (v_ff, 'evening', 'Evening wind-down', 2),
    (v_ff, 'both', 'Both — AM & PM', 3);

  -- ── PDPA: privacy notice + terms (required) + marketing (optional) ──
  INSERT INTO consent_versions (
    merchant_id, version_code, consent_type, interaction_type,
    title, preview, content, is_mandatory, active_status, order_index, published_at
  ) VALUES (
    v_merchant_id, 'rkt-privacy-v1', 'privacy_policy', 'notice',
    'Privacy notice',
    'How Rocket Club collects and uses your personal data for membership, skincare recommendations, and loyalty benefits.',
    $privacy$
<p><strong>Rocket Club — Privacy Notice</strong></p>
<p>Rocket Club (demo programme) explains how we collect, use, and disclose personal data under applicable privacy laws, including Thailand’s PDPA, when you join our lifestyle skincare membership.</p>
<p><strong>Data we collect</strong></p>
<ul>
<li>Identity and contact details you provide at signup (name, mobile, email, LINE)</li>
<li>Profile and preference answers (skin type, concerns, shopping habits, interests)</li>
<li>Loyalty activity: points, tiers, missions, redemptions, and purchase history at participating channels</li>
<li>App, campaign, and customer-service interactions</li>
</ul>
<p><strong>Why we use it</strong></p>
<ul>
<li>Operate your membership and fulfil rewards</li>
<li>Personalize product tips, offers, and content to your skin profile</li>
<li>Improve products, stores, and digital experiences</li>
<li>Meet legal and audit obligations</li>
</ul>
<p><strong>Sharing</strong></p>
<p>We may share data with affiliated brands, store partners, payment providers, and platform operators (including Rocket Innovation) who process data on our instructions. We do not sell your contact list to unrelated third-party marketers.</p>
<p><strong>Retention & rights</strong></p>
<p>We keep data while you are a member and for a reasonable period afterward. You may request access, correction, deletion, restriction, or withdrawal of consent where applicable via the member app or customer care.</p>
<p><em>Demo copy for sales and UAT — not a regulator filing.</em></p>
$privacy$,
    true, true, 1, now()
  )
  ON CONFLICT (merchant_id, version_code) DO UPDATE SET
    consent_type = EXCLUDED.consent_type,
    interaction_type = EXCLUDED.interaction_type,
    title = EXCLUDED.title,
    preview = EXCLUDED.preview,
    content = EXCLUDED.content,
    is_mandatory = EXCLUDED.is_mandatory,
    active_status = true,
    order_index = EXCLUDED.order_index,
    published_at = COALESCE(consent_versions.published_at, now())
  RETURNING id INTO v_notice;

  INSERT INTO consent_versions (
    merchant_id, version_code, consent_type, interaction_type,
    title, preview, content, is_mandatory, active_status, order_index, published_at
  ) VALUES (
    v_merchant_id, 'rkt-tos-v1', 'terms_of_service', 'required',
    'Membership terms',
    'Rules for earning points, redeeming rewards, and using Rocket Club skincare member benefits.',
    $tos$
<p><strong>Rocket Club Membership Terms</strong></p>
<p>By joining Rocket Club you agree to these terms for our lifestyle skincare loyalty programme.</p>
<ul>
<li>Your account is personal; keep login details secure and profile information accurate.</li>
<li>Points, tiers, missions, and rewards follow the rates and expiry rules shown in the app at the time of each activity.</li>
<li>Redemptions and promotions are subject to stock, eligibility, and campaign rules.</li>
<li>Misuse, fraud, or resale of benefits may lead to suspension.</li>
<li>We may update benefits or these terms with notice in the app; continued use means you accept the updated version.</li>
</ul>
<p><em>Demo programme terms for Rocket Demo merchant.</em></p>
$tos$,
    true, true, 2, now()
  )
  ON CONFLICT (merchant_id, version_code) DO UPDATE SET
    consent_type = EXCLUDED.consent_type,
    interaction_type = EXCLUDED.interaction_type,
    title = EXCLUDED.title,
    preview = EXCLUDED.preview,
    content = EXCLUDED.content,
    is_mandatory = EXCLUDED.is_mandatory,
    active_status = true,
    order_index = EXCLUDED.order_index,
    published_at = COALESCE(consent_versions.published_at, now())
  RETURNING id INTO v_tos;

  INSERT INTO consent_versions (
    merchant_id, version_code, consent_type, interaction_type,
    title, preview, content, is_mandatory, active_status, order_index, published_at
  ) VALUES (
    v_merchant_id, 'rkt-marketing-v1', 'marketing', 'optional',
    'Personalized offers & skincare tips',
    'Optional consent to receive tailored promotions, launch news, and education based on your profile.',
    $mkt$
<p><strong>Marketing & personalization</strong></p>
<p>With your consent, Rocket Club may contact you about new formulas, member-exclusive offers, events, and skincare education matched to your profile and purchase history. You can change your mind anytime in Consent Management.</p>
$mkt$,
    false, true, 3, now()
  )
  ON CONFLICT (merchant_id, version_code) DO UPDATE SET
    consent_type = EXCLUDED.consent_type,
    interaction_type = EXCLUDED.interaction_type,
    title = EXCLUDED.title,
    preview = EXCLUDED.preview,
    content = EXCLUDED.content,
    is_mandatory = EXCLUDED.is_mandatory,
    active_status = true,
    order_index = EXCLUDED.order_index,
    published_at = COALESCE(consent_versions.published_at, now())
  RETURNING id INTO v_marketing;

  DELETE FROM communication_topics
  WHERE merchant_id = v_merchant_id
    AND topic_name IN (
      'Product launches',
      'Member offers & events',
      'Skincare tips & routines',
      'Brand A',
      'Brand B',
      'Brand C',
      'Promotion news',
      'Newsletter'
    );

  INSERT INTO communication_topics (merchant_id, topic_name, description, active_status) VALUES
    (v_merchant_id, 'Brand A', 'Cleansers, toners, and daily essentials from our Brand A skincare line', true),
    (v_merchant_id, 'Brand B', 'Serums, treatments, and clinic-inspired actives from Brand B', true),
    (v_merchant_id, 'Brand C', 'SPF, body care, and fragrance-layering picks from Brand C', true),
    (v_merchant_id, 'Promotion news', 'Sales, member-only offers, points boosts, and limited-time campaigns', true),
    (v_merchant_id, 'Newsletter', 'Monthly edit: routines, ingredient spotlights, and what''s new at Rocket Club', true),
    (v_merchant_id, 'Product launches', 'New serums, SPF, and limited drops matched to your skin profile', true),
    (v_merchant_id, 'Member offers & events', 'Points boosts, boutique events, and member-only perks', true),
    (v_merchant_id, 'Skincare tips & routines', 'Routine guides, ingredient education, and seasonal care', true);

  RETURN jsonb_build_object(
    'success', true,
    'form_id', v_form_id,
    'groups', 3,
    'notice_id', v_notice,
    'tos_id', v_tos,
    'marketing_id', v_marketing
  );
END;
$fn$;
