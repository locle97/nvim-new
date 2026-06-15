#!/usr/bin/env bash
# Install the Quarker post-checkout hook into a target git repo by symlinking
# hooks/post-checkout into the repo's .git/hooks/. Symlink (not copy) so the
# hook stays current with this config.
#
# Usage: hooks/install-post-checkout.sh [target-repo-dir] [--force]
#   target-repo-dir  defaults to the current directory
#   --force          overwrite an existing post-checkout hook
set -euo pipefail

force=0
target="."
for a in "$@"; do
    case "$a" in
        --force) force=1 ;;
        *) target="$a" ;;
    esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/post-checkout"
[ -f "$src" ] || { echo "install: source hook not found at $src" >&2; exit 1; }

# Resolve the target repo's git hooks dir (absolute; works in worktrees too).
git_dir="$(cd "$target" && git rev-parse --absolute-git-dir)"
hooks_dir="$git_dir/hooks"
mkdir -p "$hooks_dir"

dest="$hooks_dir/post-checkout"
if [ -e "$dest" ] && [ "$force" -ne 1 ]; then
    echo "install: $dest already exists; re-run with --force to overwrite" >&2
    exit 1
fi

chmod +x "$src"
ln -sf "$src" "$dest"
echo "installed post-checkout hook -> $dest"
