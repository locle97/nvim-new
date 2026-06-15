#!/usr/bin/env bash
# Run from repo root: bash tests/quarker/cli_scope_spec.sh
repo="$(pwd)"
cli="$repo/lua/quarker/cli.lua"

tmp_data="$(mktemp -d)"
work="$(mktemp -d)"   # non-git temp dir => base_scope == work
cleanup() { rm -rf "$tmp_data" "$work"; }
trap cleanup EXIT

scopes_json() { find "$tmp_data" -name scopes.json 2>/dev/null | head -1; }

# --- switch --create on a missing scope: creates it and makes it active ---
out="$(cd "$work" && XDG_DATA_HOME="$tmp_data" nvim -l "$cli" scope switch feature-x --create)"
[ -z "$out" ] || { echo "FAIL: scope switch wrote to stdout: $out" >&2; exit 1; }
sj="$(scopes_json)"
[ -n "$sj" ] || { echo "FAIL: scopes.json not created" >&2; exit 1; }
grep -q '"feature-x"' "$sj" || { echo "FAIL: scope feature-x not created" >&2; cat "$sj" >&2; exit 1; }
grep -Eq '"active_scope": ?"feature-x"' "$sj" || { echo "FAIL: feature-x not active" >&2; cat "$sj" >&2; exit 1; }
echo "ok: scope switch --create creates and activates"

# --- switch --create is idempotent: re-running keeps it active, no error ---
out="$(cd "$work" && XDG_DATA_HOME="$tmp_data" nvim -l "$cli" scope switch feature-x --create)"
[ -z "$out" ] || { echo "FAIL: idempotent switch wrote to stdout: $out" >&2; exit 1; }
echo "ok: scope switch --create is idempotent"

# --- switch WITHOUT --create to a missing scope: non-zero exit ---
if (cd "$work" && XDG_DATA_HOME="$tmp_data" nvim -l "$cli" scope switch nope) 2>/dev/null; then
    echo "FAIL: switch to missing scope should exit non-zero" >&2; exit 1
fi
echo "ok: scope switch to missing scope fails"

echo "PASS cli_scope_spec"
