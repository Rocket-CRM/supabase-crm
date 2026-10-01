#!/usr/bin/env node
/**
 * Drain internal_knowledge_embedding_jobs after doc-knowledge reconcile.
 *
 * Calls doc_knowledge_drain_embeddings in many short RPC rounds (p_max_rounds=1).
 * A single long RPC hits PostgREST statement_timeout when the queue is large;
 * orchestration stays in Node, each round runs util.process_embeddings once.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */

import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const MAX_CLIENT_ROUNDS = 500;
const RPC_ARGS = {
  p_max_rounds: 1,
  p_batch_size: 20,
  p_max_requests: 10,
  p_sleep_seconds: 1,
};

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

let lastData = null;

for (let i = 0; i < MAX_CLIENT_ROUNDS; i++) {
  const { data, error } = await supabase.rpc(
    "doc_knowledge_drain_embeddings",
    RPC_ARGS
  );

  if (error) {
    console.error(
      `doc_knowledge_drain_embeddings failed on client round ${i + 1}:`,
      error.message
    );
    process.exit(1);
  }

  lastData = data;
  const remaining = Number(data?.queue_length_remaining ?? 0);
  const started = data?.started_queue_length ?? "?";

  console.log(
    `Embedding drain round ${i + 1}: started_queue=${started} remaining=${remaining}`
  );

  if (remaining === 0) {
    console.log("Embedding drain complete:", JSON.stringify(data));
    process.exit(0);
  }
}

console.error(
  `Embedding drain: ${MAX_CLIENT_ROUNDS} client rounds exhausted; last:`,
  JSON.stringify(lastData)
);
process.exit(2);
