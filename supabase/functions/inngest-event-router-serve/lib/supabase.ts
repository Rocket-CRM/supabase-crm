import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}
