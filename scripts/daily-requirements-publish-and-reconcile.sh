#!/usr/bin/env bash
# Daily: commit + push requirement corpus, then doc-knowledge reconcile (embed queue
# drains via Supabase pg_cron process-internal-knowledge-embeddings).
#
# Schedule: launchd at 21:00 local time (see scripts/install-daily-docs-sync-launchd.sh).
# Requires: Mac awake; git push access; SUPABASE_* in env file (see supabase-crm.env.example).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="${ROCKET_SUPABASE_CRM_ENV:-$HOME/.config/rocket/supabase-crm.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY. Create ${ENV_FILE} from scripts/supabase-crm.env.example" >&2
  exit 1
fi

LOG_PREFIX="[daily-docs-sync $(date '+%Y-%m-%d %H:%M:%S')]"
echo "${LOG_PREFIX} starting in ${REPO_ROOT}"

git add requirements/ docs/PRODUCT_NARRATIVE.md

if git diff --staged --quiet; then
  echo "${LOG_PREFIX} no staged doc changes; skipping commit/push"
else
  git commit -m "docs: daily sync $(date +%Y-%m-%d)"
  branch="$(git rev-parse --abbrev-ref HEAD)"
  echo "${LOG_PREFIX} pushing branch ${branch}"
  git push origin "HEAD:${branch}"
fi

cd "${REPO_ROOT}/scripts"
if [[ ! -d node_modules/@supabase ]]; then
  npm install --no-fund --no-audit
fi

echo "${LOG_PREFIX} running doc-knowledge-reconcile"
node doc-knowledge-reconcile.mjs

echo "${LOG_PREFIX} draining embedding queue"
node drain-doc-knowledge-embeddings.mjs

echo "${LOG_PREFIX} done"
