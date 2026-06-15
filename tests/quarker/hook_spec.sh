#!/usr/bin/env bash
# Run from repo root: bash tests/quarker/hook_spec.sh
repo="$(pwd)"
hook="$repo/hooks/mark-plan-files.sh"

tmp_data="$(mktemp -d)"
work="$(mktemp -d)"
cleanup() { rm -rf "$tmp_data" "$work"; }
trap cleanup EXIT

export CLAUDE_PROJECT_DIR="$repo"

plan="$work/docs/superpowers/plans/2026-01-01-demo.md"
mkdir -p "$(dirname "$plan")"
cat > "$plan" <<'PLAN'
**Files:**
- Create: `lua/demo.lua`
PLAN

# --- non-plans write: no-op, empty stdout, exit 0, no marks created ---
json_other="$(jq -n --arg p "$work/README.md" '{tool_input:{file_path:$p}}')"
out="$(cd "$work" && XDG_DATA_HOME="$tmp_data" bash "$hook" <<<"$json_other")"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: non-plans write exit $rc" >&2; exit 1; }
[ -z "$out" ] || { echo "FAIL: non-plans write produced stdout: $out" >&2; exit 1; }
if find "$tmp_data" -name default.json 2>/dev/null | grep -q .; then
  echo "FAIL: non-plans write created marks" >&2; exit 1
fi
echo "ok: non-plans write is a no-op"

# --- plan write: marks the plan's files, empty stdout, exit 0 ---
json_plan="$(jq -n --arg p "$plan" '{tool_input:{file_path:$p}}')"
out="$(cd "$work" && XDG_DATA_HOME="$tmp_data" bash "$hook" <<<"$json_plan")"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: plan write exit $rc" >&2; exit 1; }
[ -z "$out" ] || { echo "FAIL: plan write produced stdout: $out" >&2; exit 1; }
scope_json="$(find "$tmp_data" -name default.json 2>/dev/null | head -1)"
[ -n "$scope_json" ] || { echo "FAIL: plan write created no marks" >&2; exit 1; }
grep -q '"lua/demo.lua"' "$scope_json" || { echo "FAIL: demo.lua not marked" >&2; cat "$scope_json" >&2; exit 1; }
echo "ok: plan write marked plan files"

echo "PASS hook_spec"
