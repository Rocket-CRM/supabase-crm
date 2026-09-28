# Doc knowledge reconcile

Indexes local `requirements/**/*.md` (for `search_docs` + `get_section`) and `docs/PRODUCT_NARRATIVE.md` (`get_section` only) into `doc_knowledge_chunks`. Default `search_docs` stays on `requirements/`.

## Daily pipeline (recommended)

**21:00 local time** on your Mac (must be awake):

1. Commit + push `requirements/` and `docs/PRODUCT_NARRATIVE.md` if anything changed.
2. Run `doc-knowledge-reconcile.mjs` (hash-skip; queues embedding jobs for changed chunks).
3. Run `drain-doc-knowledge-embeddings.mjs` (many short `doc_knowledge_drain_embeddings` RPC rounds until the PGMQ queue is empty — avoids PostgREST timeout on large queues).

The always-on pg_cron `process-internal-knowledge-embeddings` is **disabled**. Re-enable only if you reconcile ad-hoc mid-day and need background draining (see below).

### One-time setup

```bash
mkdir -p ~/.config
cp scripts/supabase-crm.env.example ~/.config/rocket/supabase-crm.env
chmod 600 ~/.config/rocket/supabase-crm.env
# Edit: set SUPABASE_SERVICE_ROLE_KEY

cd scripts
npm install --no-fund --no-audit
./install-daily-docs-sync-launchd.sh
```

### Manual run (same as the nightly job)

```bash
./scripts/daily-requirements-publish-and-reconcile.sh
```

### Logs

`~/Library/Logs/supabase-crm-daily-docs-sync.log` and `.err.log`

## Manual reconcile only

If you only need to refresh chunks without git:

```bash
export SUPABASE_URL=https://wkevmsedchftztoolkmi.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=...
cd scripts
node doc-knowledge-reconcile.mjs
```

## After OpenAI credits are restored / ad-hoc reconcile

If you run reconcile outside the nightly job and do not want to call the drain script:

```sql
select cron.alter_job(
  (select jobid from cron.job where jobname = 'process-internal-knowledge-embeddings'),
  active := true
);
```

Or drain manually:

```bash
cd scripts && node drain-doc-knowledge-embeddings.mjs
```

## GitHub Action

`.github/workflows/doc-knowledge-reconcile.yml` is optional backup (push-triggered or schedule). Primary path is the local daily job above now that `requirements/` is committed.
