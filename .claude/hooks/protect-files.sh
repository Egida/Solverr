#!/usr/bin/env bash
# Blocks edits to sensitive or generated files.
# PreToolUse hook for Edit|Write operations.
# Exit 2 = block (deny). Exit 0 = allow, or ask when it prints an "ask" decision.

set -uo pipefail

emit() {
  # $1 = decision (deny|ask) ; $2 = reason
  local decision="$1"
  local reason="${2//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$decision" "$reason"
  # Exit 2 blocks whatever the JSON says, so an "ask" has to exit 0 or it hard-blocks instead of
  # prompting. A deny exits 2 either way, and Claude Code still takes its reason from the JSON.
  [ "$decision" = "ask" ] && exit 0
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  emit deny "jq is required for file protection hooks but is not installed."
fi

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0
# On Windows the tools pass backslash paths, which no directory pattern below would match.
FILE_PATH=${FILE_PATH//\\//}
# Lower-cased because the Windows and macOS filesystems ignore case, so .ENV is .env.
PATH_LC=$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

# The table is shared with block-dangerous-commands.sh, which applies its shell rows to shell writes;
# a missing table fails closed rather than protecting nothing.
TABLE="$(dirname "${BASH_SOURCE[0]}")/protected-paths.tsv"
[ -f "$TABLE" ] || emit deny "protected-paths.tsv is missing, so no path can be checked."
while IFS=$'\t' read -r decision scope glob reason; do
  case "$decision" in ''|\#*) continue ;; esac
  [ "$scope" = shell ] && continue
  # Unquoted on purpose: the table's globs are patterns.
  case "$PATH_LC" in
    $glob|*/$glob) emit "$decision" "$reason" ;;
  esac
done < "$TABLE"

exit 0
