#!/usr/bin/env bash
# regen_registry_supabase.sh
#
# Regenerates requirements/REGISTRY_SUPABASE.md from the live Supabase DB.
# Intended for daily cron (GitHub Actions) AND manual local runs.
#
# Usage:
#   SUPABASE_DB_URL='postgresql://postgres:<password>@db.wkevmsedchftztoolkmi.supabase.co:5432/postgres' \
#     ./scripts/regen_registry_supabase.sh
#
# Or, if you're running inside a Supabase-CLI-aware shell:
#   ./scripts/regen_registry_supabase.sh
#   (the script will try `supabase db remote query` if SUPABASE_DB_URL is unset)
#
# Output: writes requirements/REGISTRY_SUPABASE.md and prints byte size to stdout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="${REPO_ROOT}/scripts/regen_registry_supabase.sql"
OUT_FILE="${REPO_ROOT}/requirements/REGISTRY_SUPABASE.md"

if [[ ! -f "${SQL_FILE}" ]]; then
  echo "error: SQL file not found at ${SQL_FILE}" >&2
  exit 1
fi

run_with_psql() {
  # -t  tuples only (no header)
  # -A  unaligned (no padding)
  # -X  ignore .psqlrc
  # -q  quiet startup messages
  # -v ON_ERROR_STOP=1  fail on first error
  psql "${SUPABASE_DB_URL}" \
    -t -A -X -q \
    -v ON_ERROR_STOP=1 \
    -f "${SQL_FILE}"
}

if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  if ! command -v psql >/dev/null 2>&1; then
    echo "error: psql is not installed; install postgresql-client" >&2
    exit 1
  fi
  run_with_psql > "${OUT_FILE}"
elif command -v supabase >/dev/null 2>&1; then
  # Fallback path: rely on supabase CLI to execute the SQL against the linked project.
  # Requires the project to be linked via `supabase link --project-ref wkevmsedchftztoolkmi`.
  supabase db remote query --file "${SQL_FILE}" \
    --project-ref wkevmsedchftztoolkmi \
    | sed -e '/^$/d' -e '/^[[:space:]]*$/d' > "${OUT_FILE}"
else
  cat >&2 <<'EOF'
error: neither SUPABASE_DB_URL nor supabase CLI available.

To run this script you need one of:

  1. Set SUPABASE_DB_URL to the Postgres connection string for the project, and
     have `psql` installed (postgresql-client). Recommended for GitHub Actions.

  2. Install the Supabase CLI and run `supabase link --project-ref wkevmsedchftztoolkmi`.

  Inside Cursor, the simplest path is to ask the agent to run the SQL file
  via the Supabase MCP (`scripts/regen_registry_supabase.sql`) and paste the
  single returned cell into requirements/REGISTRY_SUPABASE.md.
EOF
  exit 1
fi

# Strip trailing whitespace and ensure file ends with newline.
sed -i.bak -e 's/[[:space:]]*$//' "${OUT_FILE}" && rm -f "${OUT_FILE}.bak"
[[ -n "$(tail -c1 "${OUT_FILE}")" ]] && printf '\n' >> "${OUT_FILE}"

SIZE_BYTES=$(wc -c < "${OUT_FILE}" | tr -d ' ')
echo "wrote ${OUT_FILE} (${SIZE_BYTES} bytes)"
