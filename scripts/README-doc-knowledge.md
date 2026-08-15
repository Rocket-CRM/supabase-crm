# Doc knowledge reconcile

Indexes local `requirements/**/*.md` (for `search_docs` + `get_section`) and `docs/PRODUCT_NARRATIVE.md` (`get_section` only) into `doc_knowledge_chunks`. Default `search_docs` stays on `requirements/`.

## Manual / daily (recommended)

This repo gitignores most of `requirements/*`, so GitHub Actions cannot see the corpus. Run on a machine that has the full tree:

```bash
export SUPABASE_URL=https://wkevmsedchftztoolkmi.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=...
cd scripts
npm install @supabase/supabase-js@2 --no-fund --no-audit
node doc-knowledge-reconcile.mjs
```

Hash-skip: unchanged chunks are not re-upserted (no re-embed).

Optional local launchd/cron: daily after you edit requirements.

## After OpenAI credits are restored

```sql
-- re-enable embedding worker
select cron.alter_job(
  (select jobid from cron.job where jobname = 'process-internal-knowledge-embeddings'),
  active := true
);
```

Then either wait for the queue to drain or call `select util.process_embeddings(20, 10);` a few times.

## GitHub Action

`.github/workflows/doc-knowledge-reconcile.yml` is a template only. It needs committed `requirements/` plus `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` secrets to be useful.
