-- The Marks tab of the Quarker panel.
--
-- This buffer is deliberately editable: reordering or deleting lines is how you
-- reorder or remove marks, and the buffer is synced back to Quarker whenever the
-- tab is left (tab switch or close).
local float = require("quarker.ui.float")
local M = {}

local EMPTY_MESSAGE = "No marks in this scope"

-- Get filetype icon with color
local function get_filetype_icon(filename)
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
        local icon, hl_group = devicons.get_icon(filename, vim.fn.fnamemodify(filename, ":e"), { default = true })
        return icon or "", hl_group
    end
    return "", nil
end

-- Calculate cursor position based on current file
local function get_cursor_position(marks, scope)
    local current_buf_path = vim.api.nvim_buf_get_name(0)
    if current_buf_path == "" then
        return 1
    end

    -- Normalize scope path (remove trailing slash)
    local normalized_scope = scope:gsub("/$", "")

    -- Convert current buffer to relative path
    local current_relative_path = ""
    if current_buf_path:sub(1, #normalized_scope) == normalized_scope then
        current_relative_path = current_buf_path:sub(#normalized_scope + 1)
        -- Remove leading slash
        if current_relative_path:sub(1, 1) == "/" then
            current_relative_path = current_relative_path:sub(2)
        end
    else
        -- If not in scope, use the full path
        current_relative_path = current_buf_path
    end

    -- Find matching mark
    for i, mark in ipairs(marks) do
        if mark.path == current_relative_path then
            return i
        end
    end

    return 1
end

-- Parse a mark line to extract the path
-- Format: "[N] icon filename path"
local function parse_mark_line(line)
    -- Match the pattern: [number] followed by icon, filename, and path
    local path = line:match("^%[%d+%]%s+[^%s]+%s+[^%s]+%s+(.+)$")
    return path
end

-- Generate lines from marks
local function generate_mark_lines(marks)
    local lines = {}
    local highlights = {}

    for i, mark in ipairs(marks) do
        local icon, icon_hl = get_filetype_icon(mark.name)
        local line = string.format("[%d] %s %s %s", i, icon, mark.name, mark.path)
        table.insert(lines, line)

        -- Calculate positions for highlights
        local index_end = string.len(string.format("[%d] ", i))
        local icon_start = index_end
        local icon_end = icon_start + string.len(icon)
        local filename_start = icon_end + 1
        local filename_end = filename_start + string.len(mark.name)
        local path_start = filename_end + 1

        -- Highlight icon with its color
        if icon_hl and icon ~= "" then
            table.insert(highlights, {
                line = i,
                col_start = icon_start,
                col_end = icon_end,
                hl_group = icon_hl,
            })
        end

        -- Highlight path in comment color
        table.insert(highlights, {
            line = i,
            col_start = path_start,
            col_end = -1,
            hl_group = "Comment",
        })
    end

    return lines, highlights
end

-- Sync buffer content back to marks.
-- The lookup is rebuilt from Quarker's *current* marks rather than a snapshot taken
-- when the panel opened, so a mark added while the panel is open (the git tab's `m`)
-- survives this sync instead of being parsed as unknown and dropped.
local function sync_buffer_to_marks(bufnr)
    local quarker = require("quarker")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local path_to_mark = {}
    for _, mark in ipairs(quarker.get_marks()) do
        path_to_mark[mark.path] = mark
    end

    local new_marks = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            local path = parse_mark_line(line)
            if path and path_to_mark[path] then
                table.insert(new_marks, path_to_mark[path])
            end
        end
    end

    quarker.set_marks(new_marks)
end

-- Tab bar label
function M.title(_)
    local quarker = require("quarker")
    return string.format("Marks (%s)", quarker.get_active_scope_name())
end

function M.footer()
    return "<CR> open   1-9 jump   dd/p reorder   <Tab> git"
end

function M.render(ctx)
    local quarker = require("quarker")
    local marks = quarker.get_marks()

    ctx.empty = #marks == 0

    if ctx.empty then
        float.render_lines(ctx.bufnr, { EMPTY_MESSAGE }, {
            { line = 1, col_start = 0, col_end = -1, hl_group = "Comment" },
        })
        vim.api.nvim_buf_set_option(ctx.bufnr, "modifiable", false)
        return
    end

    local lines, highlights = generate_mark_lines(marks)
    float.render_lines(ctx.bufnr, lines, highlights)
    vim.api.nvim_buf_set_option(ctx.bufnr, "modifiable", true)

    -- Land on the file you are currently in, but only the first time the tab is
    -- shown: after that the cursor is wherever you left it.
    if not ctx.positioned then
        ctx.positioned = true
        local line = get_cursor_position(marks, quarker.get_scope())
        pcall(vim.api.nvim_win_set_cursor, ctx.winid, { math.min(line, #lines), 0 })
    end
end

-- Editing the buffer *is* the edit, so the buffer is the source of truth on leave.
function M.on_leave(ctx)
    if ctx.empty then
        return
    end
    sync_buffer_to_marks(ctx.bufnr)
end

function M.keymaps(ctx)
    local quarker = require("quarker")

    -- Navigate by path rather than by buffer line: the marks may have been
    -- reordered in the buffer, and the sync above is what makes that authoritative.
    local function navigate_to(path)
        M.on_leave(ctx)
        ctx.close()

        for i, mark in ipairs(quarker.get_marks()) do
            if mark.path == path then
                quarker.navigate(i)
                return
            end
        end
    end

    local function navigate()
        if ctx.empty then
            return
        end

        local line = vim.api.nvim_win_get_cursor(ctx.winid)[1]
        local text = vim.api.nvim_buf_get_lines(ctx.bufnr, line - 1, line, false)[1]
        local path = text and text ~= "" and parse_mark_line(text) or nil

        if not path then
            vim.notify("Invalid mark line", vim.log.levels.WARN)
            return
        end
        navigate_to(path)
    end

    local function make_jump_handler(index)
        return function()
            local marks = quarker.get_marks()
            if index > #marks then
                vim.notify(string.format("Mark %d does not exist", index), vim.log.levels.WARN)
                return
            end
            navigate_to(marks[index].path)
        end
    end

    local keymaps = {
        { mode = "n", key = "<CR>", callback = navigate, desc = "Navigate to mark" },
    }

    for i = 1, 9 do
        table.insert(keymaps, {
            mode = "n",
            key = tostring(i),
            callback = make_jump_handler(i),
            desc = string.format("Jump to mark %d", i),
        })
    end

    return keymaps
end

return M
