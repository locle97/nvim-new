# Quarker hooks

Standalone hooks that drive the headless Quarker CLI (`lua/quarker/cli.lua` via `nvim -l`).

## `post-checkout` — per-branch scope switching

On every **branch** checkout, switches Quarker's active scope to a scope named
after the branch, creating it if it does not exist.

- **Branch → scope name:** the last `/`-separated segment of the branch, with any
  character outside `[A-Za-z0-9_-]` replaced by `-`.
  Examples: `feat/foo-bar` → `foo-bar`, `release/v1.2.0` → `v1-2-0`.
- File checkouts and detached HEAD are ignored. The hook never blocks a checkout
  (always exits 0); if `nvim` or the CLI is missing it prints a notice to stderr
  and skips.

### Install

From this config repo, install into any target repo (defaults to the current dir):

```bash
~/.config/nvim/hooks/install-post-checkout.sh /path/to/repo
# overwrite an existing post-checkout hook:
~/.config/nvim/hooks/install-post-checkout.sh /path/to/repo --force
```

Run it once per repo you want per-branch scopes in. The installer symlinks
`hooks/post-checkout` into the repo's `.git/hooks/`, so the same canonical script
is reused everywhere and edits to it propagate to all installed repos. The hook
resolves the CLI at `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua/quarker/cli.lua`
(override with `QUARKER_CLI`).

## `mark-plan-files.sh`

PostToolUse(Write) hook that marks a freshly-written plan's files into the active
scope. See the file header for details.
