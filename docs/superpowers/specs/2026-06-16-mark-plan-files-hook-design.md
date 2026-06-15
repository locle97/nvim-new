# Mark Plan Files Hook — Design

**Date:** 2026-06-16
**Status:** Approved (design)
**Topic:** A Claude Code PostToolUse hook that, when the `writing-plans` skill writes a plan to `docs/superpowers/plans/*.md`, parses the plan's `Files:` blocks and marks every referenced path into the current Quarker scope — so opening Neovim shows the plan's files already in the Quarker list.

## Problem

The `writing-plans` skill produces a structured plan document listing, per task, the exact files to Create/Modify/Test. Today those paths live only in the markdown. To start work in Neovim you re-find and re-mark each file by hand. We want the plan's files to be marked in Quarker automatically the moment the plan is written, with zero manual steps.

This requires reaching Quarker's on-disk state from outside the Neovim runtime. Quarker stores marks at `stdpath("data")/quarker/<sha256(git-root-or-cwd)>/<scope>.json`, relative to the git root, using `vim.fn.sha256`/`vim.json`/`vim.fn.stdpath`. Any external writer must honor that exact contract — so we reuse the plugin's own Lua via `nvim -l` rather than reimplementing it. (See the companion spec `2026-06-15-quarker-bash-cli-design.md` for the broader headless-CLI rationale; this design implements only the minimal marking slice that the hook needs.)

## Constraints & Assumptions

- `nvim` ≥ 0.9 is on `$PATH` (required for `nvim -l` Lua script mode; local is v0.12.2).
- Hooks run with the project directory as cwd, so `get_base_scope()` (`git rev-parse --show-toplevel`, else cwd) resolves the same scope Neovim would resolve interactively in that repo.
- Marks land in the **active** scope. The hook does not create or switch scopes.
- Standalone: Neovim is typically closed when the hook runs. Correct on-disk state for the next launch is sufficient; last-writer-wins, same as the plugin's own saves.
- Plans are written via the `Write` tool to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` (the `writing-plans` default).

## Chosen Approach

A PostToolUse hook (matcher `Write`) registered in the **nvim repo's project** `.claude/settings.json`. The hook filters for writes into the plans directory, then runs the real Quarker Lua headless via `nvim -l` to parse the plan and mark its files. Plan parsing lives in Lua (testable, robust), not in the shell.

Rejected alternatives:
- **Parse paths in the shell hook**, passing individual paths to `cli.lua mark` — keeps `cli.lua` to the spec's surface, but markdown parsing in bash/grep is fragile and untestable. Rejected for a Lua `mark-plan` command.
- **Global registration** in `~/.claude/settings.json` — fires in every repo, but the user chose project-only scoping to the nvim repo for now.
- **Stop hook scanning the plans dir** — decoupled from the write but fires every turn and needs recency tracking. Rejected for the precise PostToolUse(Write) trigger.

### Data flow

```
writing-plans skill
      │  Write docs/superpowers/plans/2026-…-feature.md
      ▼
PostToolUse(Write)  ── matcher "Write" ──►  hooks/mark-plan-files.sh
      │  jq tool_input.file_path; match */docs/superpowers/plans/*.md ? else exit 0
      ▼
nvim -l <config>/lua/quarker/cli.lua mark-plan <planfile>   (runs in shell cwd)
      │  parse Files: blocks → strip :ranges → dedupe → mark_file(each)
      ▼
quarker/init.lua  ── reuses sha256 / JSON / relative-path / save logic ──►
      ▼
stdpath("data")/quarker/<sha256(git-root)>/<active-scope>.json
```

## Components

### 1. `lua/quarker/init.lua` — add `M.mark_file(abspath)`

New public function mirroring `M.mark()` but taking an absolute path argument instead of reading the current buffer (`vim.fn.expand("%:p")`, which does not exist headless). Reuses the existing private helpers (`get_base_scope`, `get_active_scope_name`, `get_relative_path`, `get_marks`, `save_marks`). Dedupe behavior matches `mark()`: if the relative path is already marked in the active scope, it is a no-op. Marks into the active scope. Interactive functions remain unchanged.

Only `mark_file` is added. `unmark_file`/`toggle_file` (listed in the broader CLI spec) are not needed by this hook and are out of scope.

### 2. `lua/quarker/cli.lua` — NEW

Single Lua entrypoint for `nvim -l` script mode:

- Prepend the config's `lua/` directory to `package.path` so `require("quarker")` resolves. Derive the config dir from the script's own path (`arg[0]`) so it works regardless of cwd.
- Route `vim.notify` to stderr and silence stray `print`, so **stdout carries only intended output** and the hook never injects noise into the agent.
- `require("quarker")`.
- Parse the global `arg` table and dispatch:
  - `mark <path…>` — for each path, absolutize with `vim.fn.fnamemodify(p, ":p")` (resolves relative paths against cwd), call `require("quarker").mark_file(abspath)`.
  - `mark-plan <planfile>` — read the plan file, parse all `Files:` block paths (see rules below), dedupe, `mark_file` each.
- Set exit code via `os.exit`: `0` success, non-zero on failure (e.g. unreadable plan file → non-zero; a plan with zero `Files:` paths is success with nothing marked).

### 3. `hooks/mark-plan-files.sh` — NEW (version-controlled in this repo)

Thin PostToolUse hook body:

- Read the hook JSON from stdin; extract `tool_input.file_path` with `jq -r`.
- If the path does not match `*/docs/superpowers/plans/*.md`, exit 0 (no-op).
- Verify `nvim` exists; if not, print a clear message to stderr and exit 0 (do not break the agent turn).
- Run `nvim -l "$HOME/.config/nvim/lua/quarker/cli.lua" mark-plan "<file_path>"`.
- Always exit 0. Errors from `nvim`/parsing go to stderr only; the hook never blocks or fails the agent.

### 4. Hook registration — `.claude/settings.json` (this repo)

Add a PostToolUse entry, matcher `Write`, command pointing at `$CLAUDE_PROJECT_DIR/hooks/mark-plan-files.sh`. Project-scoped: fires only when Claude Code runs inside the nvim config repo. Written via the `update-config` skill.

## Files-Block Parsing Rules

The `writing-plans` task format is:

```markdown
**Files:**
- Create: `exact/path/to/file.lua`
- Modify: `exact/path/to/existing.lua:123-145`
- Test: `tests/exact/path/to/test.lua`
```

Rules:
- A `Files:` block is the run of lines following a line containing `**Files:**`, up to the next blank line or markdown heading.
- Within the block, each entry of the form `- Create:` / `- Modify:` / `- Test:` contributes the **backtick-quoted path** that follows.
- Strip any trailing line reference from the path: `:N` or `:start-end` (a trailing `:` followed by digits, optionally `-digits`).
- Include not-yet-created paths (Create targets). They are stored as marks and become reachable once created.
- Resolve relative paths against the repo root (cwd) when marking; absolutization happens in `mark_file`/`cli.lua`.
- Dedupe across all tasks (a path appearing in multiple tasks is marked once; `mark_file` also dedupes against existing marks).

## Error Handling & Edge Cases

| Case | Behavior |
|---|---|
| Write outside plans dir | Hook exits 0, no-op (path filter). |
| Plan file unreadable | `cli.lua mark-plan` exits non-zero, message to stderr; hook still exits 0. |
| Plan has no `Files:` blocks | Success, nothing marked. |
| Create target doesn't exist yet | Marked anyway (path stored relative to root). Documented. |
| Path outside repo root | Stored as given (mirrors plugin's `get_relative_path` fallback). |
| `nvim` missing / < 0.9 | Hook prints to stderr, exits 0 — never breaks the agent turn. |
| Path already marked | `mark_file` no-ops (dedupe), same as interactive `mark()`. |
| stdout cleanliness | `vim.notify`/`print` routed to stderr in `cli.lua`; stdout stays empty/parseable. |
| Concurrency | Neovim typically closed; no live-cache staleness; last writer wins, same as plugin saves. |

## Testing

- **Lua unit:** Against a temp `stdpath("data")`: (a) `mark_file(abspath)` round-trip — mark a file, read back via `get_marks`, assert one record with the correct relative path; mark again, assert no duplicate. (b) `mark-plan` on a sample plan fixture with multiple tasks, line-ranges, and a duplicate path — assert `<active-scope>.json` contains exactly the expected deduped, range-stripped relative paths.
- **Shell integration:** In a throwaway git repo, pipe sample PostToolUse JSON (a plans-dir write, and a non-plans write) into `mark-plan-files.sh`; assert exit 0, empty stdout, and that the plans-dir case produced the expected quarker JSON while the non-plans case produced nothing.
- **End-to-end:** Write a real plan in a test repo, open Neovim there, confirm the plan's files appear in the Quarker picker.

## Out of Scope

- The full `quarker` bash wrapper on `$PATH` and the rest of the CLI command surface (scope ops, `unmark`, `toggle`, `marks list/clear`) — the broader `2026-06-15-quarker-bash-cli-design.md` project.
- Creating or switching scopes from the hook (marks go to the active scope).
- Editing `<scope>.context.md` content.
- Global (cross-repo) hook registration — project-scoped to the nvim repo for now.
