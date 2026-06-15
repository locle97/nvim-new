# Quarker Bash CLI — Design

**Date:** 2026-06-15
**Status:** Approved (design)
**Topic:** Let external bash scripts (tmux, fzf, git hooks, project switchers) drive quarker — switch scope/context, mark/unmark files, list, and manage scopes — while Neovim is closed.

## Problem

Quarker's logic and storage contract live entirely inside the Neovim runtime:

- State is stored at `stdpath("data")/quarker/<sha256(git-root-or-cwd)>/`:
  - `scopes.json` — `{ active_scope, scopes[] }`
  - `<scope>.json` — marked files for that scope
  - `<scope>.context.md` — freeform context notes
- Marks are stored **relative to the git root**, with a specific JSON schema and a legacy-format migration path.
- All of this uses `vim.fn.sha256`, `vim.json`, `vim.fn.stdpath`.

Bash lives outside that runtime. Any integration must honor the exact storage contract or the two sides will silently disagree and corrupt each other's state.

## Constraints & Assumptions

- **Standalone usage:** scripts run while Neovim is closed. No live in-memory cache to keep in sync; correct on-disk state for the next nvim launch is sufficient. Last-writer-wins, same as the plugin's own saves.
- `nvim` ≥ 0.9 is available on `$PATH` (verified: local is v0.12.2). Required for `nvim -l` Lua script mode.
- Scope is resolved from the shell's current working directory, exactly as the plugin does (`git rev-parse --show-toplevel`, else cwd).

## Chosen Approach — Headless `nvim -l` wrapper

Reuse the real quarker Lua by running it under `nvim -l` (Lua script mode). This is zero-reimplementation: sha256, JSON schema, relative-path logic, and migration are all the plugin's own code, so the CLI **cannot drift** from the plugin — it *is* the plugin.

Rejected alternatives:
- **Reimplement the storage format in bash/python** — fast, no nvim dependency, but duplicates the storage contract in a second language; drifts and corrupts on any schema change. Highest long-term risk.
- **Extract a runtime-agnostic Lua core + standalone `lua` CLI** — true single source of truth *and* fast (no nvim startup), but a real refactor of working code (abstract away every `vim.*` call, vendor sha256+json libs). Worth it only if sub-50ms shell latency matters; it does not for these operations.

### Data flow

```
bash / tmux / fzf
      │  quarker <args>
      ▼
quarker (bash wrapper on $PATH)
      │  nvim -l <config>/lua/quarker/cli.lua <args>   (runs in shell cwd)
      ▼
cli.lua
      │  package.path += config lua dir; stub vim.notify; require("quarker"); dispatch
      ▼
quarker/init.lua  ── reuses sha256 / JSON / relative-path / migration logic ──►
      ▼
stdpath("data")/quarker/<sha256(git-root)>/{scopes.json, <scope>.json, <scope>.context.md}
```

`nvim -l` runs headless **without sourcing the user config**, passes argv in the global `arg` table, and gives full access to `vim.fn.sha256` / `vim.json` / `vim.fn.stdpath`. Headless nvim inherits the shell's cwd, so `get_base_scope()` resolves the same scope nvim would interactively.

## Components

### 1. `quarker` — bash wrapper (on `$PATH`)

Thin forwarder. Responsibilities:

- Resolve the config's `cli.lua` path (e.g. `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua/quarker/cli.lua`).
- Verify `nvim` exists and is ≥ 0.9; otherwise print a clear error to stderr and exit non-zero.
- `exec nvim -l "<cli.lua>" "$@"` so the script inherits cwd and the process exit code propagates.

### 2. `lua/quarker/cli.lua` — NEW

Single Lua entrypoint for script mode. Responsibilities:

- Prepend the config's `lua/` directory to `package.path` so `require("quarker")` resolves.
- Stub `vim.notify` (and `print` noise from the plugin) to a no-op / stderr router, so **stdout carries only intended machine output**.
- `require("quarker")` (headless-safe: `ai.lua` does all plugin work lazily inside functions; nothing heavy at module load).
- Parse the global `arg` table, dispatch to the command table below.
- Print human-readable output by default; honor `--json` / `--paths`.
- Set process exit code: `0` success, non-zero on failure (`os.exit`).

### 3. `lua/quarker/init.lua` — small additions

Today's `mark()` / `unmark()` / `toggle()` read the current buffer (`vim.fn.expand("%:p")`), which does not exist headless. Add path-accepting public functions that mirror them but take an absolute path argument:

- `M.mark_file(abspath)`
- `M.unmark_file(abspath)`
- `M.toggle_file(abspath)`

These reuse the existing private helpers (`get_base_scope`, `get_relative_path`, `get_marks`, `save_marks`). The interactive buffer-based functions remain unchanged and can be refactored to delegate to these (pass `expand("%:p")`), but that refactor is optional and must not change interactive behavior.

No other production code changes.

## Command Surface

All commands operate on the scope resolved from cwd. Exit `0` on success, non-zero on failure. Human output → stdout; errors → stderr.

### Scope (context)

| Command | Action |
|---|---|
| `quarker scope list` | List scopes; active marked with `*`. `--json` for machine output. |
| `quarker scope current` | Print active scope name only (ideal for tmux/statusline). |
| `quarker scope switch <name>` | Set active scope. Fails non-zero if scope does not exist. |
| `quarker scope create <name>` | Create scope. Validates name `^[a-zA-Z0-9_-]+$`. |
| `quarker scope delete <name>` | Delete scope. Refuses `default`. `--force` to skip confirmation. |
| `quarker scope rename <old> <new>` | Rename scope (refuses renaming `default`; validates new name). |

### Marks

| Command | Action |
|---|---|
| `quarker mark <file>` | Mark file. Path resolved to absolute, stored relative to git root. |
| `quarker unmark <file>` | Remove mark for file. |
| `quarker toggle <file>` | Toggle mark for file. |
| `quarker marks` / `quarker marks list` | List marked files in active scope. `--json` / `--paths`. |
| `quarker marks clear` | Clear all marks in active scope. `--force` to skip confirmation. |

### Output formats

- **default** — human-readable, aligned for terminal reading.
- **`--json`** — emits the underlying records (scope list or mark records) as JSON for programmatic consumption.
- **`--paths`** (marks only) — one path per line, nothing else; for piping into `fzf`, `xargs`, tmux menus.

## Error Handling & Edge Cases

| Case | Behavior |
|---|---|
| Not a git repo | Falls back to cwd as scope — same as the plugin. Documented, not an error. |
| `nvim` missing or < 0.9 | Wrapper prints clear error to stderr, exits non-zero. |
| Unknown scope on switch/delete/rename | Non-zero exit, message to stderr. |
| `mark` of a file outside the scope root | Stored as given (mirrors plugin's `get_relative_path` fallback). Documented. |
| Invalid scope name on create/rename | Non-zero exit, validation message to stderr. |
| Concurrency | nvim closed in standalone case; no live-cache staleness; last writer wins, same as plugin saves. |
| stdout cleanliness | `vim.notify`/`print` stubbed in `cli.lua`; only intended output reaches stdout — safe to parse. |

## Testing

- **Unit (Lua):** test `mark_file`/`unmark_file`/`toggle_file` against a temp `stdpath("data")` to confirm they reuse the same on-disk format the interactive functions produce (round-trip: mark via `mark_file`, read back via `get_marks`).
- **Integration (shell):** run the `quarker` wrapper in a throwaway git repo and a non-git dir; assert exit codes, stdout for `--json`/`--paths`, and that produced JSON files match the plugin's schema.
- **Cross-check:** mark a file via the CLI, open nvim in the same repo, confirm the mark appears in the picker (and vice versa) — proves the contract is honored end to end.

## Out of Scope

- Live synchronization with a running Neovim instance (RPC to an open server). Standalone-only by decision.
- Editing `<scope>.context.md` content from bash (the AI/context-note features). Only scope and mark operations are in scope.
- Reimplementing or refactoring quarker's storage into a runtime-agnostic core (the rejected Approach C).
