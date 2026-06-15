#!/usr/bin/env bash
# Run from repo root: bash tests/quarker/post_checkout_spec.sh
repo="$(pwd)"

tmp_data="$(mktemp -d)"
tmp_cfg="$(mktemp -d)"
gitrepo="$(mktemp -d)"
cleanup() { rm -rf "$tmp_data" "$tmp_cfg" "$gitrepo"; }
trap cleanup EXIT

# Make the hook resolve THIS repo's cli.lua via XDG_CONFIG_HOME/nvim/...
ln -s "$repo" "$tmp_cfg/nvim"
export XDG_CONFIG_HOME="$tmp_cfg"
export XDG_DATA_HOME="$tmp_data"

# Throwaway git repo with one commit.
cd "$gitrepo"
git init -q
git config user.email t@t
git config user.name t
git commit -q --allow-empty -m init

# Install the hook.
bash "$repo/hooks/install-post-checkout.sh" "$gitrepo" >/dev/null
[ -L "$gitrepo/.git/hooks/post-checkout" ] || { echo "FAIL: hook not installed" >&2; exit 1; }
echo "ok: installer symlinked the hook"

# Branch checkout with a slash -> scope = last path segment.
git checkout -q -b feat/foo-bar

sj="$(find "$tmp_data" -name scopes.json 2>/dev/null | head -1)"
[ -n "$sj" ] || { echo "FAIL: scopes.json not created by hook" >&2; exit 1; }
grep -q '"foo-bar"' "$sj" || { echo "FAIL: scope foo-bar not created" >&2; cat "$sj" >&2; exit 1; }
grep -Eq '"active_scope": ?"foo-bar"' "$sj" || { echo "FAIL: foo-bar not active" >&2; cat "$sj" >&2; exit 1; }
echo "ok: branch checkout created+activated scope 'foo-bar'"

echo "PASS post_checkout_spec"
