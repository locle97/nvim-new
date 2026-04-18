local float = require("quarker.ui.float")
local M = {}

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

-- Render marks to buffer
local function render_marks(bufnr, marks)
    local lines, highlights = generate_mark_lines(marks)
    float.render_lines(bufnr, lines, highlights)
end

-- Sync buffer content back to marks
local function sync_buffer_to_marks(bufnr, original_marks, quarker)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local new_marks = {}

    -- Build a lookup table from original marks by path
    local path_to_mark = {}
    for _, mark in ipairs(original_marks) do
        path_to_mark[mark.path] = mark
    end

    -- Parse each line and rebuild marks list
    for _, line in ipairs(lines) do
        -- Skip empty lines
        if line ~= "" then
            local path = parse_mark_line(line)
            if path and path_to_mark[path] then
                table.insert(new_marks, path_to_mark[path])
            end
        end
    end

    -- Update marks in quarker
    quarker.set_marks(new_marks)
end

-- Main function to show marks in floating buffer
function M.show_marks(force_cursor_line)
    local quarker = require("quarker")
    local marks = quarker.get_marks()

    if #marks == 0 then
        vim.notify("No marks found in current scope", vim.log.levels.INFO)
        return
    end

    -- Get scope info for title
    local scope_name = quarker.get_active_scope_name()
    local scope_path = quarker.get_scope()
    local title = string.format(" Quarker Marks (%s) ", scope_name)

    -- Create floating window
    local bufnr, winid = float.create_float_win({
        width_ratio = 0.6,
        height_ratio = 0.7,
        title = title,
        win_type = "marks",
    })

    -- Render marks
    render_marks(bufnr, marks)

    -- Set cursor position
    local cursor_line = force_cursor_line or get_cursor_position(marks, scope_path)
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    cursor_line = math.min(cursor_line, total_lines)
    cursor_line = math.max(cursor_line, 1)
    vim.api.nvim_win_set_cursor(winid, { cursor_line, 0 })

    -- Store original marks for syncing
    local original_marks = vim.deepcopy(marks)

    -- Setup autocmd to sync changes when leaving buffer
    local augroup = vim.api.nvim_create_augroup("QuarkerMarksSync", { clear = true })

    vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
        group = augroup,
        buffer = bufnr,
        once = true,
        callback = function()
            sync_buffer_to_marks(bufnr, original_marks, quarker)
            vim.api.nvim_del_augroup_by_id(augroup)
        end,
    })

    -- Navigate to mark under cursor
    local function navigate()
        local line = vim.api.nvim_win_get_cursor(winid)[1]
        local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line = buf_lines[line]

        if current_line and current_line ~= "" then
            local path = parse_mark_line(current_line)
            if path then
                -- Sync first so marks are updated
                sync_buffer_to_marks(bufnr, original_marks, quarker)
                float.close_float_win(winid)

                -- Find the mark index in the updated marks
                local updated_marks = quarker.get_marks()
                for i, mark in ipairs(updated_marks) do
                    if mark.path == path then
                        quarker.navigate(i)
                        return
                    end
                end
            end
        end
        vim.notify("Invalid mark line", vim.log.levels.WARN)
    end

    local function close_window()
        -- Sync changes before closing
        sync_buffer_to_marks(bufnr, original_marks, quarker)
        float.close_float_win(winid)
    end

    -- Quick jump to mark by number
    local function make_jump_handler(index)
        return function()
            if index <= #marks then
                local mark = marks[index]
                -- Sync before navigating
                sync_buffer_to_marks(bufnr, original_marks, quarker)
                float.close_float_win(winid)

                -- Find the mark index in the updated marks
                local updated_marks = quarker.get_marks()
                for i, m in ipairs(updated_marks) do
                    if m.path == mark.path then
                        quarker.navigate(i)
                        return
                    end
                end
            else
                vim.notify(string.format("Mark %d does not exist", index), vim.log.levels.WARN)
            end
        end
    end

    -- Minimal keymaps - let the buffer behave normally otherwise
    local keymaps = {
        { mode = "n", key = "<CR>", callback = navigate, desc = "Navigate to mark" },
        { mode = "n", key = "q", callback = close_window, desc = "Close and save" },
        { mode = "n", key = "<Esc>", callback = close_window, desc = "Close and save" },
    }

    -- Add number keys 1-9 for quick jump
    for i = 1, 9 do
        table.insert(keymaps, {
            mode = "n",
            key = tostring(i),
            callback = make_jump_handler(i),
            desc = string.format("Jump to mark %d", i),
        })
    end

    float.set_float_keymaps(bufnr, keymaps)
end

return M
