# Quarker Git Changes Tab — Design

**Date:** 2026-07-11
**Status:** Approved (design)
**Topic:** Extend the `<leader><leader>` Quarker modal with a second tab listing the repository's git changes, grouped into Changes and Staged Changes, with `<Tab>` switching between the marks list and the git list.

## Problem

`<leader><leader>` opens the Quarker marks float — a fast, keyboard-driven way to reach the files you care about. The files you care about *right now*, mid-change, are usually the dirty ones, and today reaching those means a different tool (nvim-tree's git panel, or codediff's explorer sidebar). The marks modal is already the muscle-memory entry point; git changes belong in it.

codediff.nvim's explorer shows exactly the presentation we want — section headers with counts, file icon, filename, dim directory, right-aligned status letter — so the git tab mirrors it.

## Constraints & Assumptions

- Scope is Quarker's base scope: `git rev-parse --show-toplevel`, else cwd (`quarker.get_scope()`).
- codediff.nvim is installed (`lua/plugins/codediff.lua`) and is the diff viewer.
- nvim-web-devicons is installed (the marks tab already uses it for file icons).
- nvim-tree is installed, so its git highlight groups exist and are themed.
- The marks buffer is *editable*: reordering marks works by editing lines, and the buffer is synced back to Quarker on close. Nothing in this design may compromise that.

## Chosen Approach

**One float; tabs swap the buffer's content.** Window ownership moves out of `ui/marks.lua` into a new `ui/panel.lua` that owns the float, the tab bar, and `<Tab>`. Each tab is a module that knows how to render itself and what keymaps it wants; the panel never knows what is inside a tab.

Rejected alternatives:

- **Two separate floats, `<Tab>` closes one and opens the other.** Smallest diff, but visible teardown/rebuild on every switch, cursor state lost, and the marks sync-on-`BufLeave` autocmd fires on each toggle.
- **Stack both lists in one buffer, no tabs.** Not what was asked for, and git lines inside the editable marks buffer would poison `sync_buffer_to_marks`.

### The tab bar lives in the border title

Not in the buffer. A tab-bar line inside the editable marks buffer is something the user can delete or reorder into. `nvim_open_win`'s `title` accepts a list of `[text, hl_group]` chunks, so the tab bar is rendered there:

```
╭──────────  Marks  │  Git Changes (3)  ──────────╮
```

Active tab highlighted, inactive dimmed. No interference with buffer editing, and it reads as tabs.

## Components

```
lua/quarker/git.lua          NEW  — data layer: status(), stage(path), unstage(path)
lua/quarker/ui/panel.lua     NEW  — owns the float, tab bar, <Tab> switching
lua/quarker/ui/git.lua       NEW  — the Git Changes tab: render + keymaps
lua/quarker/ui/marks.lua     EDIT — becomes a tab module; loses window ownership
lua/quarker/ui/float.lua     EDIT — title accepts highlighted chunks; "panel" win_type
```

### `quarker/git.lua` — the only module that shells out

- `status()` runs `git status --porcelain=v1 -z --untracked-files=all` from the base scope and returns `{ unstaged = {…}, staged = {…} }`, each entry `{ path, name, dir, status }`. `path` is relative to the scope; `name` is the basename; `dir` is the dirname (`""` at the root); `status` is a single letter (`M`, `A`, `D`, `R`, `U` for untracked).
- The `-z` form is NUL-separated, so paths with spaces or unicode need no quote-unwrapping.
- A file with both staged and unstaged edits appears in **both** lists — git's own two-column model, and what the codediff UI does.
- Renames carry their new path (the `-z` rename record is `XY<NUL>new<NUL>old`).
- `stage(path)` → `git add --`, `unstage(path)` → `git restore --staged --`. Both return `ok, stderr`.
- Not a git repo, or git missing: `status()` returns `nil, err`.

### Tab module interface

Each tab exposes:

- `title(ctx)` → label text for the tab bar (e.g. `"Git Changes (3)"`).
- `render(ctx)` → draws into `ctx.bufnr`; owns its own highlights and `modifiable` state.
- `keymaps(ctx)` → list of `{ mode, key, callback, desc }` for the panel to bind.
- `on_leave(ctx)` (optional) → the marks tab syncs its buffer back to Quarker here.

`ctx` carries `bufnr`, `winid`, and a `refresh()` the tab can call to redraw itself and the tab bar in place.

The marks tab keeps its editable-buffer behavior; the git tab is `nomodifiable`.

## The Git tab

```
Changes (1)
  󰢱 utils.lua  lua/                                    M
Staged Changes (0)
```

Section headers show counts and are always present, even when empty. Entries are file icon (devicons, themed), filename, dim directory (`Comment`), and the status letter right-aligned at the window edge.

Status letters use nvim-tree's git highlight groups so they inherit the colorscheme: `NvimTreeGitDirty` (M), `NvimTreeGitStaged` (A/R staged), `NvimTreeGitNew` (U), `NvimTreeGitDeleted` (D).

### Keys

| Key | Action |
| --- | --- |
| `<CR>` | Open the file, close the modal |
| `d` | Open codediff for the file against HEAD, close the modal |
| `s` | Stage / unstage the entry, refresh in place (modal stays open) |
| `m` | Mark the file into Quarker (it appears in the Marks tab) |
| `r` | Re-run `git status` and redraw |
| `<Tab>` | Switch tab |
| `q` / `<Esc>` | Close |

`s` takes its direction from the section the entry is in: under Changes it's `git add`, under Staged Changes it's `git restore --staged`. Staging several files in a row is the common case, so the modal stays open and the cursor line is clamped to the new line count.

`<CR>`/`d`/`s`/`m` on a section header line do nothing but a quiet notify.

## Behavior changes to existing code

- `<leader><leader>` **always opens on the Marks tab** (deterministic muscle memory), and now opens **even when there are no marks**. Today `show_marks` notifies "No marks found in current scope" and returns, which would leave no way to reach the git tab. Empty marks render as a single dim "No marks in this scope" line.
- `<Tab>` inside the float shadows `<C-i>` (jump-forward), which is meaningless in a modal.
- Marks sync is preserved *and* extended: switching to the git tab and back must not drop or reorder marks, so the panel runs the marks tab's `on_leave` on every tab switch, not only on window close.

## Error handling

- Not a git repository / git not on `$PATH`: the Git tab renders one line, "Not a git repository"; `s`, `d`, `m`, `<CR>` are no-ops there.
- A failing `git add` / `git restore` surfaces its stderr via `vim.notify` at ERROR level, and the list refreshes anyway so the UI never shows a stale state it believes in.
- A file listed by git that is no longer readable (deleted): `<CR>` notifies rather than opening an empty buffer.

## Testing

`quarker/git.lua` is pure enough for the repo's existing `nvim -l` spec style (`tests/quarker/*_spec.lua`): build a temp repo, produce a modified file, an untracked file, a staged file, and a file that is both staged and modified, then assert the shape of `status()`, plus a `stage`/`unstage` round-trip and a path-with-spaces case.

The UI modules are not unit-tested, consistent with the rest of `quarker/ui`; they are verified by driving the actual modal.
