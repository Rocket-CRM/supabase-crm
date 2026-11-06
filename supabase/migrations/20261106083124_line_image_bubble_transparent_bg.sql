-- LINE flex image bubbles: transparent block background so transparent PNGs
-- from Content Library do not render on LINE's default white block.
-- Only the image-only bubbles change (linked image in fn_render_blocks_as_line_messages,
-- image block in fn_render_blocks_as_line_flex). #00000000 validated against
-- LINE /v2/bot/message/validate/push (200; an invalid color returns 400).

CREATE OR REPLACE FUNCTION public.fn_render_blocks_as_line_flex(p_blocks jsonb, p_channel_key text DEFAULT 'line'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_bubbles jsonb := '[]'::jsonb;
    v_text_body jsonb := '[]'::jsonb;
    v_text_comp jsonb;
    v_block jsonb;
    v_bubble jsonb;
    v_item jsonb;
    v_rendered jsonb;
    v_body_contents jsonb;
    v_field jsonb;
    v_fields_box jsonb;
    v_link_url text;
    v_btn jsonb;
    v_btn_items jsonb;
    v_button_source jsonb;
    v_rendered_btn jsonb;
    v_card_btn_count integer;
    v_list_items jsonb;
    v_list_item jsonb;
    v_cards jsonb;
    v_card_count integer;
    v_title text;
    v_subtitle text;
    v_description text;
    v_badge text;
    v_text text;
    v_caption text;
BEGIN
    IF p_blocks IS NULL OR p_blocks = '[]'::jsonb THEN
        RETURN NULL;
    END IF;

    FOR v_block IN SELECT * FROM jsonb_array_elements(p_blocks)
    LOOP
        -- Flush packed text bubble before any non-text block
        IF COALESCE(v_block->>'type', '') <> 'text' AND jsonb_array_length(v_text_body) > 0 THEN
            v_bubbles := v_bubbles || jsonb_build_array(
                jsonb_build_object(
                    'type', 'bubble',
                    'size', 'kilo',
                    'body', jsonb_build_object(
                        'type', 'box',
                        'layout', 'vertical',
                        'spacing', 'sm',
                        'contents', v_text_body
                    )
                )
            );
            v_text_body := '[]'::jsonb;
        END IF;

        CASE v_block->>'type'
        WHEN 'card' THEN
            v_link_url := COALESCE(v_block->'link'->'platform_urls'->>p_channel_key, v_block->'link'->>'default_url', v_block->'link'->>p_channel_key, v_block->'link'->>'default');
            v_fields_box := '[]'::jsonb;
            IF v_block->'fields' IS NOT NULL THEN
                FOR v_field IN SELECT * FROM jsonb_array_elements(v_block->'fields')
                LOOP
                    v_title := public.fn_strip_html(COALESCE(v_field->>'label', ''));
                    v_text := public.fn_strip_html(COALESCE(v_field->>'value', ''));
                    IF v_title <> '' OR v_text <> '' THEN
                        v_fields_box := v_fields_box || jsonb_build_array(jsonb_build_object('type', 'box', 'layout', 'horizontal', 'spacing', 'sm', 'contents', jsonb_build_array(jsonb_build_object('type', 'text', 'text', CASE WHEN v_title = '' THEN ' ' ELSE v_title END, 'size', 'sm', 'color', '#999999', 'flex', 2, 'wrap', true), jsonb_build_object('type', 'text', 'text', CASE WHEN v_text = '' THEN ' ' ELSE v_text END, 'size', 'sm', 'align', 'end', 'flex', 3, 'wrap', true))));
                    END IF;
                END LOOP;
            END IF;

            v_body_contents := '[]'::jsonb;
            v_title := public.fn_strip_html(COALESCE(v_block->>'title', ''));
            IF v_title <> '' THEN
                v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_title, 'weight', 'bold', 'size', 'lg', 'wrap', true));
            END IF;

            IF v_block->>'subtitle' IS NOT NULL THEN
                v_subtitle := public.fn_strip_html(v_block->>'subtitle');
                IF v_subtitle <> '' THEN
                    v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_subtitle, 'size', 'sm', 'color', '#999999', 'wrap', true));
                END IF;
            END IF;

            IF v_block->>'description' IS NOT NULL THEN
                v_description := public.fn_strip_html(v_block->>'description');
                IF v_description <> '' THEN
                    v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_description, 'size', 'sm', 'color', '#666666', 'wrap', true));
                END IF;
            END IF;

            IF jsonb_array_length(v_fields_box) > 0 THEN
                v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'separator', 'margin', 'md')) || v_fields_box;
            END IF;

            IF v_block->>'badge' IS NOT NULL THEN
                v_badge := public.fn_strip_html(v_block->>'badge');
                IF v_badge <> '' THEN
                    v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_badge, 'size', 'xs', 'color', '#1DB446', 'weight', 'bold', 'margin', 'md'));
                END IF;
            END IF;

            -- LINE rejects empty text components; if no body text, omit body when hero/footer exist
            IF jsonb_array_length(v_body_contents) > 0 THEN
                v_bubble := jsonb_build_object('type', 'bubble', 'size', 'kilo', 'body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'sm', 'contents', v_body_contents));
            ELSE
                v_bubble := jsonb_build_object('type', 'bubble', 'size', 'kilo');
            END IF;

            IF v_block->>'image_url' IS NOT NULL THEN
                -- fit: show full artwork (cover was cropping titles burned into images)
                v_bubble := v_bubble || jsonb_build_object('hero', jsonb_build_object('type', 'image', 'url', v_block->>'image_url', 'size', 'full', 'aspectRatio', fn_line_flex_aspect_ratio(v_block->>'image_aspect_ratio', '4:3'), 'aspectMode', 'fit'));
            END IF;

            v_btn_items := '[]'::jsonb;
            IF v_block->'buttons' IS NOT NULL AND jsonb_typeof(v_block->'buttons') = 'array' THEN
                v_card_btn_count := 0;
                FOR v_btn IN SELECT * FROM jsonb_array_elements(v_block->'buttons')
                LOOP
                    EXIT WHEN v_card_btn_count >= 2;
                    v_rendered_btn := fn_render_line_flex_button(v_btn, p_channel_key);
                    IF v_rendered_btn IS NOT NULL THEN
                        v_btn_items := v_btn_items || jsonb_build_array(v_rendered_btn);
                        v_card_btn_count := v_card_btn_count + 1;
                    END IF;
                END LOOP;
            END IF;
            IF jsonb_array_length(v_btn_items) > 0 THEN
                v_bubble := v_bubble || jsonb_build_object('footer', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'sm', 'contents', v_btn_items));
            ELSIF v_link_url IS NOT NULL AND v_link_url <> '' THEN
                v_bubble := v_bubble || jsonb_build_object('footer', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'sm', 'contents', jsonb_build_array(jsonb_build_object('type', 'button', 'style', 'primary', 'color', '#1DB446', 'action', jsonb_build_object('type', 'uri', 'label', 'View', 'uri', v_link_url)))));
            END IF;

            -- Skip entirely empty bubbles (no body, hero, or footer)
            IF v_bubble ? 'body' OR v_bubble ? 'hero' OR v_bubble ? 'footer' THEN
                v_bubbles := v_bubbles || jsonb_build_array(v_bubble);
            END IF;

        WHEN 'carousel' THEN
            v_cards := COALESCE(v_block->'cards', v_block->'items');
            v_card_count := 0;
            IF v_cards IS NOT NULL THEN
                FOR v_item IN SELECT * FROM jsonb_array_elements(v_cards)
                LOOP
                    EXIT WHEN v_card_count >= 10;
                    v_rendered := fn_render_blocks_as_line_flex(jsonb_build_array(COALESCE(v_item, '{}'::jsonb) || jsonb_build_object('type', COALESCE(v_item->>'type', 'card'))), p_channel_key);
                    IF v_rendered IS NOT NULL THEN
                        IF v_rendered->>'type' = 'carousel' AND v_rendered->'contents' IS NOT NULL THEN
                            v_bubbles := v_bubbles || v_rendered->'contents';
                        ELSIF v_rendered->>'type' = 'bubble' THEN
                            v_bubbles := v_bubbles || jsonb_build_array(v_rendered);
                        END IF;
                    END IF;
                    v_card_count := v_card_count + 1;
                END LOOP;
            END IF;

        WHEN 'hero' THEN
            v_body_contents := '[]'::jsonb;
            v_title := public.fn_strip_html(COALESCE(v_block->>'title', ''));
            IF v_title <> '' THEN
                v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_title, 'weight', 'bold', 'size', 'xl', 'wrap', true));
            END IF;
            IF v_block->>'subtitle' IS NOT NULL THEN
                v_subtitle := public.fn_strip_html(v_block->>'subtitle');
                IF v_subtitle <> '' THEN
                    v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_subtitle, 'size', 'md', 'wrap', true));
                END IF;
            END IF;
            IF v_block->>'description' IS NOT NULL THEN
                v_description := public.fn_strip_html(v_block->>'description');
                IF v_description <> '' THEN
                    v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_description, 'size', 'sm', 'color', '#666666', 'wrap', true));
                END IF;
            END IF;
            IF jsonb_array_length(v_body_contents) > 0 THEN
                v_bubble := jsonb_build_object('type', 'bubble', 'size', 'mega', 'body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'md', 'contents', v_body_contents));
            ELSE
                v_bubble := jsonb_build_object('type', 'bubble', 'size', 'mega');
            END IF;
            IF v_block->>'image_url' IS NOT NULL THEN
                v_bubble := v_bubble || jsonb_build_object('hero', jsonb_build_object('type', 'image', 'url', v_block->>'image_url', 'size', 'full', 'aspectRatio', '20:13', 'aspectMode', 'fit'));
            END IF;
            IF v_bubble ? 'body' OR v_bubble ? 'hero' THEN
                v_bubbles := v_bubbles || jsonb_build_array(v_bubble);
            END IF;

        WHEN 'buttons' THEN
            v_btn_items := '[]'::jsonb;
            v_button_source := COALESCE(v_block->'buttons', v_block->'items');
            IF v_button_source IS NOT NULL THEN
                FOR v_btn IN SELECT * FROM jsonb_array_elements(v_button_source)
                LOOP
                    v_rendered_btn := fn_render_line_flex_button(v_btn, p_channel_key);
                    IF v_rendered_btn IS NOT NULL THEN
                        v_btn_items := v_btn_items || jsonb_build_array(v_rendered_btn);
                    END IF;
                END LOOP;
            END IF;
            IF jsonb_array_length(v_btn_items) > 0 THEN
                v_bubbles := v_bubbles || jsonb_build_array(jsonb_build_object('type', 'bubble', 'size', 'kilo', 'body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'sm', 'contents', v_btn_items)));
            END IF;

        WHEN 'text' THEN
            -- Accumulate into one message-box bubble (heading + caption stay together)
            v_text := public.fn_strip_html(COALESCE(v_block->>'content', ''));
            IF v_text <> '' THEN
                v_text_comp := jsonb_build_object(
                    'type', 'text',
                    'text', v_text,
                    'size', CASE COALESCE(v_block->>'style', 'normal') WHEN 'heading' THEN 'xl' WHEN 'caption' THEN 'xs' ELSE 'md' END,
                    'weight', CASE WHEN v_block->>'style' = 'heading' THEN 'bold' ELSE 'regular' END,
                    'wrap', true
                );
                IF v_block->>'style' = 'caption' THEN
                    v_text_comp := v_text_comp || jsonb_build_object('color', '#999999');
                END IF;
                IF jsonb_array_length(v_text_body) > 0 THEN
                    v_text_comp := v_text_comp || jsonb_build_object('margin', 'md');
                END IF;
                v_text_body := v_text_body || jsonb_build_array(v_text_comp);
            END IF;

        WHEN 'list' THEN
            v_list_items := '[]'::jsonb;
            IF v_block->>'title' IS NOT NULL THEN
                v_title := public.fn_strip_html(v_block->>'title');
                IF v_title <> '' THEN
                    v_list_items := v_list_items || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_title, 'weight', 'bold', 'size', 'lg', 'wrap', true), jsonb_build_object('type', 'separator', 'margin', 'md'));
                END IF;
            END IF;
            IF v_block->'items' IS NOT NULL THEN
                FOR v_list_item IN SELECT * FROM jsonb_array_elements(v_block->'items')
                LOOP
                    IF v_list_item->>'label' IS NOT NULL AND v_list_item->>'value' IS NOT NULL THEN
                        v_list_items := v_list_items || jsonb_build_array(jsonb_build_object('type', 'box', 'layout', 'horizontal', 'spacing', 'sm', 'margin', 'md', 'contents', jsonb_build_array(jsonb_build_object('type', 'text', 'text', public.fn_strip_html(v_list_item->>'label'), 'size', 'sm', 'color', '#999999', 'flex', 3, 'wrap', true), jsonb_build_object('type', 'text', 'text', public.fn_strip_html(v_list_item->>'value'), 'size', 'sm', 'flex', 5, 'wrap', true))));
                    ELSIF v_list_item->>'title' IS NOT NULL THEN
                        v_title := public.fn_strip_html(v_list_item->>'title');
                        IF v_title <> '' THEN
                            v_list_items := v_list_items || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_title, 'size', 'sm', 'margin', 'md', 'wrap', true));
                        END IF;
                    END IF;
                END LOOP;
            END IF;
            IF jsonb_array_length(v_list_items) > 0 THEN
                v_bubbles := v_bubbles || jsonb_build_array(jsonb_build_object('type', 'bubble', 'size', 'kilo', 'body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'sm', 'contents', v_list_items)));
            END IF;

        WHEN 'callout' THEN
            v_body_contents := '[]'::jsonb;
            v_title := public.fn_strip_html(COALESCE(v_block->>'title', ''));
            IF v_title <> '' THEN
                v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_title, 'weight', 'bold', 'size', 'md', 'wrap', true));
            END IF;
            IF v_block->>'content' IS NOT NULL THEN
                v_text := public.fn_strip_html(v_block->>'content');
                IF v_text <> '' THEN
                    v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text, 'size', 'sm', 'wrap', true));
                END IF;
            END IF;
            IF v_block->>'promo_code' IS NOT NULL THEN
                v_body_contents := v_body_contents || jsonb_build_array(jsonb_build_object('type', 'text', 'text', 'Code: ' || (v_block->>'promo_code'), 'size', 'lg', 'weight', 'bold', 'color', '#1DB446', 'margin', 'md'));
            END IF;
            IF jsonb_array_length(v_body_contents) > 0 THEN
                v_bubbles := v_bubbles || jsonb_build_array(jsonb_build_object('type', 'bubble', 'size', 'kilo', 'body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'spacing', 'sm', 'backgroundColor', CASE COALESCE(v_block->>'style', 'info') WHEN 'promo' THEN '#FFF8E1' WHEN 'warning' THEN '#FFF3E0' WHEN 'success' THEN '#E8F5E9' ELSE '#E3F2FD' END, 'cornerRadius', 'lg', 'paddingAll', 'lg', 'contents', v_body_contents)));
            END IF;

        WHEN 'image' THEN
            IF v_block->>'image_url' IS NOT NULL THEN
                v_bubble := jsonb_build_object('type', 'bubble', 'size', 'kilo', 'hero', jsonb_build_object('type', 'image', 'url', v_block->>'image_url', 'size', 'full', 'aspectRatio', fn_line_flex_aspect_ratio(v_block->>'image_aspect_ratio', '4:3'), 'aspectMode', 'fit'), 'styles', jsonb_build_object('hero', jsonb_build_object('backgroundColor', '#00000000')));
                IF v_block->>'caption' IS NOT NULL THEN
                    v_caption := public.fn_strip_html(v_block->>'caption');
                    IF v_caption <> '' THEN
                        v_bubble := v_bubble || jsonb_build_object('body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'contents', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_caption, 'size', 'sm', 'color', '#999999', 'wrap', true))), 'styles', jsonb_build_object('hero', jsonb_build_object('backgroundColor', '#00000000'), 'body', jsonb_build_object('backgroundColor', '#00000000')));
                    END IF;
                END IF;
                v_bubbles := v_bubbles || jsonb_build_array(v_bubble);
            END IF;

        WHEN 'video' THEN
            IF v_block->>'video_url' IS NOT NULL THEN
                v_bubbles := v_bubbles || jsonb_build_array(jsonb_build_object('type', 'bubble', 'size', 'kilo', 'hero', jsonb_build_object('type', 'video', 'url', v_block->>'video_url', 'previewUrl', COALESCE(v_block->>'thumbnail_url', v_block->>'video_url'), 'altContent', jsonb_build_object('type', 'image', 'url', COALESCE(v_block->>'thumbnail_url', v_block->>'video_url'), 'size', 'full', 'aspectRatio', '16:9', 'aspectMode', 'cover'))));
            END IF;

        WHEN 'separator' THEN
            v_bubbles := v_bubbles || jsonb_build_array(jsonb_build_object('type', 'bubble', 'size', 'kilo', 'body', jsonb_build_object('type', 'box', 'layout', 'vertical', 'contents', jsonb_build_array(CASE COALESCE(v_block->>'style', 'line') WHEN 'space' THEN jsonb_build_object('type', 'box', 'layout', 'vertical', 'height', '20px', 'contents', '[]'::jsonb) ELSE jsonb_build_object('type', 'separator') END))));

        ELSE
            NULL;
        END CASE;
    END LOOP;

    -- Flush trailing packed text
    IF jsonb_array_length(v_text_body) > 0 THEN
        v_bubbles := v_bubbles || jsonb_build_array(
            jsonb_build_object(
                'type', 'bubble',
                'size', 'kilo',
                'body', jsonb_build_object(
                    'type', 'box',
                    'layout', 'vertical',
                    'spacing', 'sm',
                    'contents', v_text_body
                )
            )
        );
    END IF;

    IF jsonb_array_length(v_bubbles) = 0 THEN
        RETURN NULL;
    ELSIF jsonb_array_length(v_bubbles) = 1 THEN
        RETURN v_bubbles->0;
    ELSE
        RETURN jsonb_build_object('type', 'carousel', 'contents', v_bubbles);
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_render_blocks_as_line_messages(p_blocks jsonb, p_channel_key text DEFAULT 'line'::text, p_alt_text text DEFAULT 'Message'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_messages jsonb := '[]'::jsonb;
  v_text_parts text[] := ARRAY[]::text[];
  v_flex_blocks jsonb := '[]'::jsonb;
  v_block jsonb;
  v_type text;
  v_text text;
  v_caption text;
  v_flex jsonb;
  v_alt text;
  v_url text;
  v_link_url text;
BEGIN
  IF p_blocks IS NULL OR jsonb_typeof(p_blocks) <> 'array' OR jsonb_array_length(p_blocks) = 0 THEN
    RETURN '[]'::jsonb;
  END IF;

  v_alt := COALESCE(NULLIF(btrim(p_alt_text), ''), 'Message');

  FOR v_block IN SELECT * FROM jsonb_array_elements(p_blocks)
  LOOP
    v_type := COALESCE(v_block->>'type', '');

    IF v_type = 'text' THEN
      IF jsonb_array_length(v_flex_blocks) > 0 THEN
        v_flex := public.fn_render_blocks_as_line_flex(v_flex_blocks, p_channel_key);
        IF v_flex IS NOT NULL THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object(
            'type', 'flex',
            'altText', v_alt,
            'contents', v_flex
          ));
        END IF;
        v_flex_blocks := '[]'::jsonb;
      END IF;
      v_text := public.fn_strip_html(COALESCE(v_block->>'content', ''));
      IF v_text <> '' THEN
        v_text_parts := array_append(v_text_parts, v_text);
      END IF;

    ELSIF v_type = 'image' THEN
      v_url := NULLIF(v_block->>'image_url', '');

      -- Flush pending card/hero flex blocks: they are their own message.
      IF jsonb_array_length(v_flex_blocks) > 0 THEN
        v_flex := public.fn_render_blocks_as_line_flex(v_flex_blocks, p_channel_key);
        IF v_flex IS NOT NULL THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object(
            'type', 'flex',
            'altText', v_alt,
            'contents', v_flex
          ));
        END IF;
        v_flex_blocks := '[]'::jsonb;
      END IF;

      IF v_url IS NOT NULL THEN
        v_text := NULL;
        IF cardinality(v_text_parts) > 0 THEN
          v_text := LEFT(array_to_string(v_text_parts, E'\n\n'), 5000);
          v_text_parts := ARRAY[]::text[];
        END IF;

        -- Text + image go out as separate messages. Default order is image
        -- first so the trailing text message drives the chat-list preview
        -- (plain image messages have no altText and show as "sent a photo").
        -- An image block can keep the authored order via text_position='before'.
        IF v_text IS NOT NULL AND btrim(v_text) <> '' AND v_block->>'text_position' = 'before' THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text));
          v_text := NULL;
        END IF;

        -- Same link resolution as card blocks in fn_render_blocks_as_line_flex.
        v_link_url := NULLIF(btrim(COALESCE(
          v_block->'link'->'platform_urls'->>p_channel_key,
          v_block->'link'->>'default_url',
          v_block->'link'->>p_channel_key,
          v_block->'link'->>'default'
        )), '');

        IF v_link_url IS NOT NULL THEN
          -- A plain image message cannot be tappable; a linked image goes out as
          -- a flex bubble whose hero carries the URI action. The hero follows the
          -- stored aspect ratio with aspectMode fit, matching the admin preview.
          v_messages := v_messages || jsonb_build_array(jsonb_build_object(
            'type', 'flex',
            'altText', LEFT(COALESCE(NULLIF(v_block->>'alt_text', ''), NULLIF(v_block->>'caption', ''), v_alt), 400),
            'contents', jsonb_build_object(
              'type', 'bubble',
              'size', 'giga',
              'hero', jsonb_build_object(
                'type', 'image',
                'url', v_url,
                'size', 'full',
                'aspectRatio', public.fn_line_flex_aspect_ratio(v_block->>'image_aspect_ratio', '4:3'),
                'aspectMode', 'fit',
                'action', jsonb_build_object('type', 'uri', 'label', 'Open', 'uri', v_link_url)
              ),
              'styles', jsonb_build_object('hero', jsonb_build_object('backgroundColor', '#00000000'))
            )
          ));
        ELSE
          v_messages := v_messages || jsonb_build_array(jsonb_build_object(
            'type', 'image',
            'originalContentUrl', v_url,
            'previewImageUrl', COALESCE(NULLIF(v_block->>'thumbnail_url', ''), v_url)
          ));
        END IF;

        IF v_text IS NOT NULL AND btrim(v_text) <> '' THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text));
        END IF;

        IF v_block->>'caption' IS NOT NULL THEN
          v_caption := public.fn_strip_html(v_block->>'caption');
          IF v_caption <> '' THEN
            v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', LEFT(v_caption, 5000)));
          END IF;
        END IF;
      END IF;

    ELSIF v_type = 'card' THEN
      IF cardinality(v_text_parts) > 0 THEN
        v_text := LEFT(array_to_string(v_text_parts, E'\n\n'), 5000);
        IF btrim(v_text) <> '' THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text));
        END IF;
        v_text_parts := ARRAY[]::text[];
      END IF;
      v_flex_blocks := v_flex_blocks || jsonb_build_array(v_block);

    ELSIF v_type = 'carousel' THEN
      IF cardinality(v_text_parts) > 0 THEN
        v_text := LEFT(array_to_string(v_text_parts, E'\n\n'), 5000);
        IF btrim(v_text) <> '' THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text));
        END IF;
        v_text_parts := ARRAY[]::text[];
      END IF;
      IF jsonb_array_length(v_flex_blocks) > 0 THEN
        v_flex := public.fn_render_blocks_as_line_flex(v_flex_blocks, p_channel_key);
        IF v_flex IS NOT NULL THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object(
            'type', 'flex',
            'altText', v_alt,
            'contents', v_flex
          ));
        END IF;
        v_flex_blocks := '[]'::jsonb;
      END IF;
      v_flex := public.fn_render_blocks_as_line_flex(jsonb_build_array(v_block), p_channel_key);
      IF v_flex IS NOT NULL THEN
        v_messages := v_messages || jsonb_build_array(jsonb_build_object(
          'type', 'flex',
          'altText', v_alt,
          'contents', v_flex
        ));
      END IF;

    ELSIF v_type IN ('hero', 'buttons', 'list', 'callout', 'video', 'separator') THEN
      IF cardinality(v_text_parts) > 0 THEN
        v_text := LEFT(array_to_string(v_text_parts, E'\n\n'), 5000);
        IF btrim(v_text) <> '' THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text));
        END IF;
        v_text_parts := ARRAY[]::text[];
      END IF;
      IF jsonb_array_length(v_flex_blocks) > 0 THEN
        v_flex := public.fn_render_blocks_as_line_flex(v_flex_blocks, p_channel_key);
        IF v_flex IS NOT NULL THEN
          v_messages := v_messages || jsonb_build_array(jsonb_build_object(
            'type', 'flex',
            'altText', v_alt,
            'contents', v_flex
          ));
        END IF;
        v_flex_blocks := '[]'::jsonb;
      END IF;
      v_flex := public.fn_render_blocks_as_line_flex(jsonb_build_array(v_block), p_channel_key);
      IF v_flex IS NOT NULL THEN
        v_messages := v_messages || jsonb_build_array(jsonb_build_object(
          'type', 'flex',
          'altText', v_alt,
          'contents', v_flex
        ));
      END IF;
    END IF;
  END LOOP;

  IF cardinality(v_text_parts) > 0 THEN
    v_text := LEFT(array_to_string(v_text_parts, E'\n\n'), 5000);
    IF btrim(v_text) <> '' THEN
      v_messages := v_messages || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text));
    END IF;
  END IF;
  IF jsonb_array_length(v_flex_blocks) > 0 THEN
    v_flex := public.fn_render_blocks_as_line_flex(v_flex_blocks, p_channel_key);
    IF v_flex IS NOT NULL THEN
      v_messages := v_messages || jsonb_build_array(jsonb_build_object(
        'type', 'flex',
        'altText', v_alt,
        'contents', v_flex
      ));
    END IF;
  END IF;

  RETURN v_messages;
END;
$function$;
