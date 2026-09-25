import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createDrpongHandler } from "./lib/drpong-handler.ts";

Deno.serve(createDrpongHandler());
