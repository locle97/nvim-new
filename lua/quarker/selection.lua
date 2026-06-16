-- Interactive "mark files from a visual selection" flow.
-- Parsing is delegated to quarker.plan_parser; this module owns the editor
-- side: reading the visual range, computing per-path status, confirming the
-- marks, and rendering the confirm float.
local M = {}

local function get_quarker()
    return require("quarker")
end

-- Build a set of currently-marked relative paths for O(1) lookup.
local function marked_set()
    local set = {}
    for _, mark in ipairs(get_quarker().get_marks()) do
        set[mark.path] = true
    end
    return set
end

-- For each relative path, report whether it is already marked in the active
-- scope and whether it currently exists on disk. Existence is informational
-- only — missing paths are still markable (plans reference files to create).
-- Returns: { { path = string, marked = bool, exists = bool }, ... }
function M.compute_statuses(paths)
    local base = get_quarker().get_scope()
    local marked = marked_set()
    local rows = {}

    for _, path in ipairs(paths) do
        local abs = base .. "/" .. path
        table.insert(rows, {
            path = path,
            marked = marked[path] == true,
            exists = vim.fn.filereadable(abs) == 1,
        })
    end

    return rows
end

-- Mark every relative path into the active scope, regardless of on-disk
-- existence. Reuses quarker.mark_file (returns true when newly added, false
-- when already marked) so the on-disk format cannot drift.
-- Returns: { added = number, duplicate = number }
function M.confirm_marks(paths)
    local base = get_quarker().get_scope()
    local added, duplicate = 0, 0

    for _, path in ipairs(paths) do
        local abs = base .. "/" .. path
        if get_quarker().mark_file(abs) then
            added = added + 1
        else
            duplicate = duplicate + 1
        end
    end

    return { added = added, duplicate = duplicate }
end

-- Return the text of the current/last visual selection as a single string.
-- Line-wise is sufficient: paths live inside backticks within the lines.
function M.get_visual_text()
    local mode = vim.fn.mode()
    local s_line, e_line
    if mode == "v" or mode == "V" or mode == "\22" then
        s_line = vim.fn.line("v")
        e_line = vim.fn.line(".")
    else
        s_line = vim.fn.line("'<")
        e_line = vim.fn.line("'>")
    end

    if s_line == 0 or e_line == 0 then
        return ""
    end
    if s_line > e_line then
        s_line, e_line = e_line, s_line
    end

    local lines = vim.api.nvim_buf_get_lines(0, s_line - 1, e_line, false)
    return table.concat(lines, "\n")
end

-- Render the confirm preview float for the given status rows. On confirm,
-- marks the paths and notifies a summary; on cancel, closes without marking.
local function open_confirm_float(rows)
    local float = require("quarker.ui.float")

    local lines = {}
    for _, row in ipairs(rows) do
        local tags = {}
        table.insert(tags, row.marked and "marked" or "new")
        if not row.exists then
            table.insert(tags, "missing")
        end
        table.insert(lines, string.format("  [%s] %s", table.concat(tags, ", "), row.path))
    end

    local title = string.format(" Quarker: mark %d file(s) ", #rows)
    local footer = " y / <CR> confirm   q / <Esc> cancel "

    local bufnr, winid = float.create_float_win({
        width_ratio = 0.6,
        height_ratio = math.min(0.7, math.max(0.2, (#rows + 4) / vim.opt.lines:get())),
        title = title,
        footer = footer,
        win_type = "mark_select",
    })

    float.render_lines(bufnr, lines, nil)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

    local paths = {}
    for _, row in ipairs(rows) do
        table.insert(paths, row.path)
    end

    local function close()
        float.close_float_win(winid)
    end

    local function confirm()
        close()
        local result = M.confirm_marks(paths)
        vim.notify(
            string.format("Quarker: %d marked, %d already marked", result.added, result.duplicate),
            vim.log.levels.INFO
        )
    end

    float.set_float_keymaps(bufnr, {
        { mode = "n", key = "y",     callback = confirm, desc = "Quarker: confirm marks" },
        { mode = "n", key = "<CR>",  callback = confirm, desc = "Quarker: confirm marks" },
        { mode = "n", key = "q",     callback = close,   desc = "Quarker: cancel" },
        { mode = "n", key = "<Esc>", callback = close,   desc = "Quarker: cancel" },
    })
end

-- Entry point for the visual-mode keymap: read the selection, parse paths,
-- and open the confirm float. No-ops with a notice when nothing parses.
function M.mark_from_visual()
    local text = M.get_visual_text()
    local paths = require("quarker.plan_parser").extract_paths_from_text(text)

    if #paths == 0 then
        vim.notify("Quarker: no file paths found in selection", vim.log.levels.WARN)
        return
    end

    local rows = M.compute_statuses(paths)
    open_confirm_float(rows)
end

return M
