#!/usr/bin/env bash
# Quarker: mark a freshly-written plan's files into the active scope.
# Registered as a PostToolUse(Write) hook. Never blocks the agent: always exit 0.

input="$(cat)"

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Only act on writes into a writing-plans plans directory.
case "$file_path" in
    */docs/superpowers/plans/*.md) ;;
    *) exit 0 ;;
esac

if ! command -v nvim >/dev/null 2>&1; then
    echo "mark-plan-files: nvim not found on PATH; skipping" >&2
    exit 0
fi

cli="${CLAUDE_PROJECT_DIR:-$HOME/.config/nvim}/lua/quarker/cli.lua"
if [ ! -f "$cli" ]; then
    echo "mark-plan-files: cli not found at $cli; skipping" >&2
    exit 0
fi

# Route any cli stdout to stderr so the hook itself emits nothing on stdout.
nvim -l "$cli" mark-plan "$file_path" >&2 \
    || echo "mark-plan-files: marking failed for $file_path" >&2

exit 0
