#!/usr/bin/env bash
# Run from repo root: bash tests/quarker/cli_spec.sh
repo="$(pwd)"
cli="$repo/lua/quarker/cli.lua"

tmp_data="$(mktemp -d)"
work="$(mktemp -d)"   # non-git temp dir => base_scope == work
cleanup() { rm -rf "$tmp_data" "$work"; }
trap cleanup EXIT

find_scope_json() { find "$tmp_data" -name default.json 2>/dev/null | head -1; }

# --- mark command ---
out="$(cd "$work" && XDG_DATA_HOME="$tmp_data" nvim -l "$cli" mark src/foo.lua)"
[ -z "$out" ] || { echo "FAIL: mark wrote to stdout: $out" >&2; exit 1; }
scope_json="$(find_scope_json)"
[ -n "$scope_json" ] || { echo "FAIL: scope json not created" >&2; exit 1; }
grep -q '"src/foo.lua"' "$scope_json" || { echo "FAIL: mark did not store src/foo.lua" >&2; cat "$scope_json" >&2; exit 1; }
echo "ok: mark stored relative path"

# --- mark-plan command ---
rm -rf "${tmp_data:?}/nvim"   # reset marks
plan="$work/docs/superpowers/plans/2026-01-01-x.md"
mkdir -p "$(dirname "$plan")"
cat > "$plan" <<'PLAN'
**Files:**
- Create: `lua/a.lua`
- Modify: `lua/b.lua:10-20`
PLAN
out="$(cd "$work" && XDG_DATA_HOME="$tmp_data" nvim -l "$cli" mark-plan "$plan")"
[ -z "$out" ] || { echo "FAIL: mark-plan wrote to stdout: $out" >&2; exit 1; }
scope_json="$(find_scope_json)"
[ -n "$scope_json" ] || { echo "FAIL: mark-plan created no marks" >&2; exit 1; }
grep -q '"lua/a.lua"' "$scope_json" || { echo "FAIL: mark-plan missing lua/a.lua" >&2; cat "$scope_json" >&2; exit 1; }
grep -q '"lua/b.lua"' "$scope_json" || { echo "FAIL: mark-plan missing lua/b.lua" >&2; cat "$scope_json" >&2; exit 1; }
grep -q '10-20' "$scope_json" && { echo "FAIL: line range not stripped" >&2; cat "$scope_json" >&2; exit 1; }
echo "ok: mark-plan parsed and stored paths"

echo "PASS cli_spec"
