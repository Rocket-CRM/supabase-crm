CREATE OR REPLACE FUNCTION public.cs_trigger_deliver_outbound_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_credential_id uuid;
  v_service_name text;
  v_channel text;
  v_channel_key text;
  v_service_role_key text;
  v_message_payload jsonb;
  v_delivery_mode text;
  v_line_messages jsonb;
  v_messages_array jsonb;
  v_msg jsonb;
  v_post_body jsonb;
BEGIN
  IF NEW.sender_type <> 'agent' THEN
    RETURN NEW;
  END IF;

  IF NEW.message_type = 'note' THEN
    RETURN NEW;
  END IF;

  SELECT merchant_id, credential_id
  INTO v_merchant_id, v_credential_id
  FROM cs_conversations
  WHERE id = NEW.conversation_id;

  IF v_merchant_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_channel := 'LINE';
  v_channel_key := 'line';
  IF v_credential_id IS NOT NULL THEN
    SELECT service_name INTO v_service_name
    FROM merchant_credentials WHERE id = v_credential_id;
    IF v_service_name IS NOT NULL THEN
      v_channel := CASE v_service_name
        WHEN 'line_messaging' THEN 'LINE'
        WHEN 'tiktok' THEN 'TIKTOK'
        WHEN 'shopee' THEN 'SHOPEE'
        WHEN 'lazada' THEN 'LAZADA'
        WHEN 'twilio' THEN 'SMS'
        ELSE 'LINE'
      END;
      v_channel_key := CASE v_service_name
        WHEN 'line_messaging' THEN 'line'
        WHEN 'tiktok' THEN 'tiktok'
        WHEN 'shopee' THEN 'shopee'
        WHEN 'lazada' THEN 'lazada'
        WHEN 'twilio' THEN 'sms'
        ELSE 'web'
      END;
    END IF;
  END IF;

  v_delivery_mode := COALESCE(NEW.metadata->>'delivery_mode', 'standard');

  IF v_delivery_mode = 'rich_content' AND v_channel = 'LINE' THEN
    -- Same renderer the workflow/broadcast path uses: sequential LINE messages
    -- (text/image plain, linked image as tappable imagemap or flex hero,
    -- text_position ordering), then mapped to the OutboundMessage shape
    -- messaging-service accepts (same mapping as the AMP executor's ampMessageToOutbound).
    v_line_messages := fn_render_blocks_as_line_messages(
      NEW.metadata->'rich_content'->'blocks',
      v_channel_key,
      LEFT(COALESCE(NEW.content, ''), 400)
    );
    IF v_line_messages IS NOT NULL AND jsonb_array_length(v_line_messages) > 0 THEN
      v_messages_array := '[]'::jsonb;
      FOR v_msg IN SELECT * FROM jsonb_array_elements(v_line_messages) LOOP
        IF v_msg->>'type' = 'text' THEN
          v_messages_array := v_messages_array || jsonb_build_object(
            'type', 'text',
            'content', COALESCE(v_msg->>'text', '')
          );
        ELSIF v_msg->>'type' = 'image' THEN
          v_messages_array := v_messages_array || jsonb_build_object(
            'type', 'image',
            'content', COALESCE(v_msg->>'originalContentUrl', ''),
            'metadata', jsonb_build_object('previewImageUrl', v_msg->>'previewImageUrl')
          );
        ELSIF v_msg->>'type' = 'flex' THEN
          v_messages_array := v_messages_array || jsonb_build_object(
            'type', 'flex',
            'content', COALESCE(v_msg->>'altText', 'Message'),
            'metadata', jsonb_build_object(
              'altText', COALESCE(v_msg->>'altText', 'Message'),
              'contents', v_msg->'contents'
            )
          );
        ELSIF v_msg->>'type' = 'imagemap' THEN
          v_messages_array := v_messages_array || jsonb_build_object(
            'type', 'imagemap',
            'content', COALESCE(v_msg->>'altText', 'Message'),
            'metadata', jsonb_build_object(
              'altText', COALESCE(v_msg->>'altText', 'Message'),
              'baseUrl', v_msg->>'baseUrl',
              'baseSize', v_msg->'baseSize',
              'actions', v_msg->'actions'
            )
          );
        END IF;
      END LOOP;
      IF jsonb_array_length(v_messages_array) = 0 THEN
        v_messages_array := NULL;
      END IF;
    END IF;
    IF v_messages_array IS NULL THEN
      v_message_payload := jsonb_build_object('type', 'text', 'content', NEW.content);
    END IF;

  ELSIF v_delivery_mode = 'platform_native' AND v_channel IN ('SHOPEE', 'LAZADA', 'TIKTOK') THEN
    v_message_payload := jsonb_build_object(
      'type', 'text',
      'content', NEW.content,
      'metadata', jsonb_build_object('native_items', COALESCE(NEW.metadata->'native_items', '[]'::jsonb))
    );

  ELSIF v_delivery_mode IN ('rich_content', 'platform_native') THEN
    v_message_payload := jsonb_build_object('type', 'text', 'content', NEW.content);

  ELSE
    v_message_payload := jsonb_build_object(
      'type', COALESCE(NEW.message_type, 'text'),
      'content', NEW.content
    );
    IF NEW.metadata->>'media_url' IS NOT NULL THEN
      v_message_payload := v_message_payload || jsonb_build_object(
        'metadata', jsonb_build_object(
          'media_url', NEW.metadata->>'media_url',
          'media_mime_type', NEW.metadata->>'media_mime_type'
        )
      );
    END IF;
  END IF;

  v_post_body := jsonb_build_object(
    'merchant_id', v_merchant_id,
    'channel', v_channel,
    'recipient', jsonb_build_object('conversation_id', NEW.conversation_id),
    'source', 'agent_trigger',
    'reference_id', NEW.conversation_id
  );
  IF v_messages_array IS NOT NULL THEN
    v_post_body := v_post_body || jsonb_build_object('messages', v_messages_array);
  ELSE
    v_post_body := v_post_body || jsonb_build_object('message', v_message_payload);
  END IF;

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://messaging-service-li40.onrender.com/send',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      body := v_post_body
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cs_trigger_deliver_outbound_message error: %', SQLERRM;
  RETURN NEW;
END;
$function$;
