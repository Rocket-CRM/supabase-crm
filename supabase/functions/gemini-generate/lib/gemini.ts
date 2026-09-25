import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

export const GEMINI_DEFAULT_MODEL = "gemini-3.5-flash";
export const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta";

export type GeminiRole = "user" | "model";

export interface GeminiContentPart {
  text?: string;
  inlineData?: { mimeType: string; data: string };
}

export interface GeminiMessage {
  role: GeminiRole;
  parts: GeminiContentPart[];
}

export interface GeminiGenerateOptions {
  /** Plain string or multi-turn contents for generateContent. */
  contents: string | GeminiMessage[];
  model?: string;
  systemInstruction?: string;
  temperature?: number;
  maxOutputTokens?: number;
  /** Override Vault/env lookup (tests only). */
  apiKey?: string;
}

export interface GeminiGenerateResult {
  text: string;
  model: string;
  finishReason: string | null;
  usage: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
  };
  raw: unknown;
}

let cachedKey: string | null = null;

function normalizeContents(
  contents: string | GeminiMessage[],
): GeminiMessage[] {
  if (typeof contents === "string") {
    return [{ role: "user", parts: [{ text: contents }] }];
  }
  return contents;
}

export function extractGeminiText(raw: unknown): string {
  const response = raw as {
    candidates?: Array<{
      content?: { parts?: Array<{ text?: string }> };
    }>;
  };
  const parts = response?.candidates?.[0]?.content?.parts ?? [];
  return parts.map((p) => p.text ?? "").join("").trim();
}

/** Read gemini_api_key from Vault via service-role RPC, with env fallback. */
export async function getGeminiApiKey(
  supabase: SupabaseClient,
): Promise<string> {
  if (cachedKey) return cachedKey;

  const envKey = Deno.env.get("GEMINI_API_KEY");
  if (envKey) {
    cachedKey = envKey;
    return cachedKey;
  }

  const { data, error } = await supabase.rpc("internal_knowledge_runtime_secret", {
    p_name: "gemini_api_key",
  });
  if (error || !data) {
    throw new Error(
      `Failed to fetch gemini_api_key: ${error?.message ?? "empty"}`,
    );
  }

  cachedKey = data as string;
  return cachedKey;
}

/** Call Gemini generateContent (REST). Defaults to gemini-3.5-flash. */
export async function callGemini(
  supabase: SupabaseClient,
  options: GeminiGenerateOptions,
): Promise<GeminiGenerateResult> {
  const model = options.model ?? GEMINI_DEFAULT_MODEL;
  const apiKey = options.apiKey ?? await getGeminiApiKey(supabase);

  const body: Record<string, unknown> = {
    contents: normalizeContents(options.contents),
  };

  if (options.systemInstruction) {
    body.systemInstruction = {
      parts: [{ text: options.systemInstruction }],
    };
  }

  const generationConfig: Record<string, unknown> = {};
  if (options.temperature !== undefined) {
    generationConfig.temperature = options.temperature;
  }
  if (options.maxOutputTokens !== undefined) {
    generationConfig.maxOutputTokens = options.maxOutputTokens;
  }
  if (Object.keys(generationConfig).length > 0) {
    body.generationConfig = generationConfig;
  }

  const url =
    `${GEMINI_API_BASE}/models/${model}:generateContent`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
  });

  const raw = await response.json().catch(() => ({}));

  if (!response.ok) {
    const message = (raw as { error?: { message?: string } })?.error?.message ??
      JSON.stringify(raw);
    throw new Error(`Gemini ${response.status}: ${message}`);
  }

  const typed = raw as {
    candidates?: Array<{ finishReason?: string }>;
    usageMetadata?: {
      promptTokenCount?: number;
      candidatesTokenCount?: number;
      totalTokenCount?: number;
    };
  };

  return {
    text: extractGeminiText(raw),
    model,
    finishReason: typed.candidates?.[0]?.finishReason ?? null,
    usage: typed.usageMetadata ?? {},
    raw,
  };
}
