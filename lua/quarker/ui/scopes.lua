local float = require("quarker.ui.float")
local M = {}

-- Get the number of marks in a scope
-- @param base_scope string Base scope path
-- @param scope_name string Scope name
-- @return number Number of marks in the scope
local function get_marks_count(base_scope, scope_name)
    local marks_file = vim.fn.stdpath("data") .. "/quarker/" .. vim.fn.sha256(base_scope) .. "/" .. scope_name .. ".json"

    if vim.fn.filereadable(marks_file) == 1 then
        local file = io.open(marks_file, "r")
        if file then
            local content = file:read("*all")
            file:close()
            local success, data = pcall(vim.json.decode, content)
            if success and data and data.marks then
                return #data.marks
            end
        end
    end

    return 0
end

-- Parse a scope line to extract the scope name
-- Format: "scope_name (N marks) [active]?" or just "scope_name"
local function parse_scope_line(line)
    -- Match scope name (everything before the first space or parenthesis)
    local scope_name = line:match("^([^%s%(]+)")
    return scope_name
end

-- Render scopes to buffer
-- @param bufnr number Buffer number
-- @param scopes table Array of scope names
-- @param active_scope string Active scope name
-- @param base_scope string Base scope path
-- @return number Line number of active scope
local function render_scopes(bufnr, scopes, active_scope, base_scope)
    local lines = {}
    local highlights = {}
    local active_line = 1

    for i, scope_name in ipairs(scopes) do
        local count = get_marks_count(base_scope, scope_name)
        local is_active = (scope_name == active_scope)
        local marker = is_active and " [active]" or ""
        local line = string.format("%s (%d marks)%s", scope_name, count, marker)
        table.insert(lines, line)

        -- Highlight active scope
        if is_active then
            active_line = i
            table.insert(highlights, {
                line = i,
                col_start = 0,
                col_end = -1,
                hl_group = "String",
            })
        end
    end

    float.render_lines(bufnr, lines, highlights)
    return active_line
end

-- Main function to show scopes in floating buffer
function M.show_scopes()
    local quarker = require("quarker")
    local scopes, active_scope = quarker.list_scopes()

    if #scopes == 0 then
        vim.notify("No scopes found", vim.log.levels.INFO)
        return
    end

    local base_scope = quarker.get_scope()
    local title = " Quarker Scopes "

    -- Create floating window
    local bufnr, winid = float.create_float_win({
        width_ratio = 0.5,
        height_ratio = 0.6,
        title = title,
        win_type = "scopes",
    })

    -- Render scopes and get active line
    local active_line = render_scopes(bufnr, scopes, active_scope, base_scope)

    -- Set cursor to active scope
    vim.api.nvim_win_set_cursor(winid, { active_line, 0 })

    -- Store original scopes for reference
    local original_scopes = vim.deepcopy(scopes)

    -- Switch to scope under cursor
    local function switch_scope()
        local line = vim.api.nvim_win_get_cursor(winid)[1]
        local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line = buf_lines[line]

        if current_line and current_line ~= "" then
            local scope_name = parse_scope_line(current_line)
            if scope_name then
                -- Check if this scope exists
                for _, s in ipairs(original_scopes) do
                    if s == scope_name then
                        float.close_float_win(winid)
                        quarker.switch_scope(scope_name)
                        return
                    end
                end
            end
        end
        vim.notify("Invalid scope line", vim.log.levels.WARN)
    end

    local function close_window()
        float.close_float_win(winid)
    end

    local function create_scope()
        vim.ui.input({ prompt = "New scope name: " }, function(name)
            if name and name ~= "" then
                if quarker.create_scope(name) then
                    -- Refresh the buffer
                    local new_scopes, new_active = quarker.list_scopes()
                    original_scopes = vim.deepcopy(new_scopes)
                    render_scopes(bufnr, new_scopes, new_active, base_scope)
                end
            end
        end)
    end

    local function rename_scope()
        local line = vim.api.nvim_win_get_cursor(winid)[1]
        local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line = buf_lines[line]

        if not current_line or current_line == "" then
            return
        end

        local old_name = parse_scope_line(current_line)
        if not old_name then
            return
        end

        if old_name == "default" then
            vim.notify("Cannot rename the default scope", vim.log.levels.ERROR)
            return
        end

        vim.ui.input({ prompt = string.format("Rename '%s' to: ", old_name) }, function(new_name)
            if new_name and new_name ~= "" then
                if quarker.rename_scope(old_name, new_name) then
                    -- Refresh the buffer
                    local new_scopes, new_active = quarker.list_scopes()
                    original_scopes = vim.deepcopy(new_scopes)
                    render_scopes(bufnr, new_scopes, new_active, base_scope)
                end
            end
        end)
    end

    local function delete_scope()
        local line = vim.api.nvim_win_get_cursor(winid)[1]
        local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line = buf_lines[line]

        if not current_line or current_line == "" then
            return
        end

        local scope_name = parse_scope_line(current_line)
        if not scope_name then
            return
        end

        if scope_name == "default" then
            vim.notify("Cannot delete the default scope", vim.log.levels.ERROR)
            return
        end

        local choice = vim.fn.confirm(
            string.format("Delete scope '%s'?", scope_name),
            "&Yes\n&No",
            2
        )

        if choice == 1 then
            quarker.delete_scope(scope_name)
            -- Refresh the buffer
            local new_scopes, new_active = quarker.list_scopes()
            original_scopes = vim.deepcopy(new_scopes)
            render_scopes(bufnr, new_scopes, new_active, base_scope)
            -- Adjust cursor if needed
            local total_lines = vim.api.nvim_buf_line_count(bufnr)
            local cursor_line = math.min(line, total_lines)
            cursor_line = math.max(cursor_line, 1)
            vim.api.nvim_win_set_cursor(winid, { cursor_line, 0 })
        end
    end

    -- Minimal keymaps
    local keymaps = {
        { mode = "n", key = "<CR>", callback = switch_scope, desc = "Switch to scope" },
        { mode = "n", key = "q", callback = close_window, desc = "Close window" },
        { mode = "n", key = "<Esc>", callback = close_window, desc = "Close window" },
        { mode = "n", key = "a", callback = create_scope, desc = "Add new scope" },
        { mode = "n", key = "r", callback = rename_scope, desc = "Rename scope" },
        { mode = "n", key = "x", callback = delete_scope, desc = "Delete scope" },
    }

    float.set_float_keymaps(bufnr, keymaps)
end

return M
