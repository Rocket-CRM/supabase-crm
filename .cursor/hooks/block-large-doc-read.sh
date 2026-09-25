#!/bin/bash
# Block full-reads of large requirement docs and registries.
# Allows reads that pass `offset` and `limit` (scoped reads) or that target small files (<30KB).
# Aligns with .cursor/rules/12-doc-search.mdc.
#
# Input (stdin JSON, from beforeReadFile hook):
#   { "tool_input": { "path": "...", "offset": <int|null>, "limit": <int|null>, ... }, ... }
#
# Output (stdout JSON):
#   { "permission": "allow" }                          -- proceed
#   { "permission": "deny", "agent_message": "..." }   -- block with guidance
#
# Fail-open: any internal error returns allow.

set -u
input=$(cat 2>/dev/null || true)

if [[ -z "$input" ]]; then
  echo '{ "permission": "allow" }'
  exit 0
fi

# Need jq; if missing, fail open.
if ! command -v jq >/dev/null 2>&1; then
  echo '{ "permission": "allow" }'
  exit 0
fi

path=$(echo "$input" | jq -r '.tool_input.path // .tool_input.target_file // empty' 2>/dev/null)
offset=$(echo "$input" | jq -r '.tool_input.offset // empty' 2>/dev/null)
limit=$(echo "$input" | jq -r '.tool_input.limit // empty' 2>/dev/null)

if [[ -z "$path" ]]; then
  echo '{ "permission": "allow" }'
  exit 0
fi

# Resolve path relative to workspace if not absolute.
if [[ "$path" != /* ]]; then
  resolved="$PWD/$path"
else
  resolved="$path"
fi

# Pattern match against the banned list.
banned=0
case "$path" in
  *requirements/INDEX_FUNCTION.md*) banned=1 ;;
  *requirements/INDEX_DOMAIN.md*)   banned=1 ;;
  *requirements/REGISTRY_SUPABASE.md*) banned=1 ;;
  *requirements/domains/_index.md*) banned=1 ;;
esac

# Also block any requirements/<Domain>.md over 30KB
if [[ "$banned" -eq 0 ]] && [[ "$path" == *requirements/*.md ]] && [[ "$path" != *requirements/feature-docs/* ]] && [[ "$path" != *requirements/domains/* ]] && [[ "$path" != *CHANGELOG.md ]] && [[ "$path" != *REGISTRY_RENDER.md ]] && [[ "$path" != *CURSOR_RULES_PRINCIPLES.md ]]; then
  if [[ -f "$resolved" ]]; then
    size=$(wc -c < "$resolved" 2>/dev/null | tr -d ' ')
    if [[ -n "$size" ]] && [[ "$size" -gt 30000 ]]; then
      banned=1
    fi
  fi
fi

if [[ "$banned" -eq 0 ]]; then
  echo '{ "permission": "allow" }'
  exit 0
fi

# If scoped (offset+limit provided), allow.
if [[ -n "$offset" ]] && [[ -n "$limit" ]] && [[ "$offset" != "null" ]] && [[ "$limit" != "null" ]]; then
  echo '{ "permission": "allow" }'
  exit 0
fi

# Block with guidance.
cat <<EOF
{
  "permission": "deny",
  "agent_message": "Read blocked by .cursor/hooks/block-large-doc-read.sh. The file \`$path\` is on the no-full-read list per .cursor/rules/12-doc-search.mdc (registries, INDEX_FUNCTION.md, large requirement docs >30KB). Use Grep first to find the relevant section, then Read with offset+limit. For function/table lookup, grep REGISTRY_SUPABASE.md. For business rules, heading-grep the domain doc with 'rg -n ^# requirements/<Doc>.md' then read at offset.",
  "user_message": "Full-read of $path blocked. Agent will switch to grep-first."
}
EOF
exit 0
