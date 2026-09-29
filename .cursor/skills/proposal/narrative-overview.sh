#!/usr/bin/env bash
# Prints the summary layer of docs/PRODUCT_NARRATIVE.md: each module's intro and
# each capability's Overview + Purpose (or "What it enables"), without journeys,
# configuration tables, or examples. ~6k of ~36k words.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
awk '
/^## |^### / { p = 1; print; next }
/^#### / { p = 0 }
/^\*\*(User Journey|How it works|Configurations & Rules|What differentiates it|Key controls|Example|Operating rules|Limitations|What the brand can configure \(by domain\)|Reports by domain|Overview \(detail inventory\))\*\*/ { p = 0 }
p
' "$root/docs/PRODUCT_NARRATIVE.md"
