// gemini-generate: synchronous Gemini generateContent helper endpoint.
// Reads gemini_api_key from Supabase Vault via internal_knowledge_runtime_secret.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  callGemini,
  type GeminiGenerateOptions,
  type GeminiMessage,
} from "./lib/gemini.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

interface RequestBody {
  text?: string;
  contents?: GeminiMessage[];
  model?: string;
  system_instruction?: string;
  temperature?: number;
  max_output_tokens?: number;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as RequestBody;

    const contents: GeminiGenerateOptions["contents"] = body.contents ??
      (body.text ? body.text : null);
    if (!contents) {
      return new Response(
        JSON.stringify({ error: "text (string) or contents (GeminiMessage[]) required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const result = await callGemini(supabase, {
      contents,
      model: body.model,
      systemInstruction: body.system_instruction,
      temperature: body.temperature,
      maxOutputTokens: body.max_output_tokens,
    });

    return new Response(
      JSON.stringify({
        text: result.text,
        model: result.model,
        finish_reason: result.finishReason,
        usage: result.usage,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("gemini-generate error", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
