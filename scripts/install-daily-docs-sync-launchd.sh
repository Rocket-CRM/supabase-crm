#!/usr/bin/env bash
# Install or reload the 21:00 local daily docs sync job (launchd).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME}"
LABEL="com.rocket.supabase-crm.daily-docs-sync"
TEMPLATE="${REPO_ROOT}/scripts/launchd/com.rocket.supabase-crm.daily-docs-sync.plist"
DEST="${HOME_DIR}/Library/LaunchAgents/${LABEL}.plist"

mkdir -p "${HOME_DIR}/Library/LaunchAgents" "${HOME_DIR}/Library/Logs"

sed \
  -e "s|__REPO_ROOT__|${REPO_ROOT}|g" \
  -e "s|__HOME__|${HOME_DIR}|g" \
  "${TEMPLATE}" > "${DEST}"

chmod +x "${REPO_ROOT}/scripts/daily-requirements-publish-and-reconcile.sh"

launchctl bootout "gui/$(id -u)" "${DEST}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${DEST}"
launchctl enable "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo "Installed ${DEST}"
echo "Runs daily at 21:00 local time when this Mac is awake."
echo "Logs: ~/Library/Logs/supabase-crm-daily-docs-sync.log"
echo "Ensure ~/.config/rocket/supabase-crm.env exists (see scripts/supabase-crm.env.example)."
