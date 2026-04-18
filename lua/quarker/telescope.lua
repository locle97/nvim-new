local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local quarker = require("quarker")

-- Get filetype icon with color
local function get_filetype_icon(filename)
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
        local icon, hl_group = devicons.get_icon(filename, vim.fn.fnamemodify(filename, ":e"), { default = true })
        return icon or "", hl_group
    end
    return "", nil
end

local M = {}

-- ============================================================================
-- Scope Management Picker
-- ============================================================================

-- Custom actions for scope picker
local function switch_to_scope(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        actions.close(prompt_bufnr)
        quarker.switch_scope(selection.value)
    end
end

local function create_new_scope(prompt_bufnr)
    actions.close(prompt_bufnr)
    vim.ui.input({ prompt = "New scope name: " }, function(input)
        if input and input ~= "" then
            if quarker.create_scope(input) then
                -- Refresh the picker
                M.scope_manager()
            end
        end
    end)
end

local function delete_selected_scope(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        local scope_name = selection.value
        if scope_name == "default" then
            vim.notify("Cannot delete the default scope", vim.log.levels.ERROR)
            return
        end

        local choice = vim.fn.confirm(string.format("Delete scope '%s'?", scope_name), "&Yes\n&No", 2)
        if choice == 1 then
            actions.close(prompt_bufnr)
            if quarker.delete_scope(scope_name) then
                -- Refresh the picker
                M.scope_manager()
            end
        end
    end
end

local function rename_selected_scope(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        local old_name = selection.value
        if old_name == "default" then
            vim.notify("Cannot rename the default scope", vim.log.levels.ERROR)
            return
        end

        actions.close(prompt_bufnr)
        vim.ui.input({ prompt = string.format("Rename '%s' to: ", old_name) }, function(input)
            if input and input ~= "" then
                if quarker.rename_scope(old_name, input) then
                    -- Refresh the picker
                    M.scope_manager()
                end
            end
        end)
    end
end

-- Custom previewer for scope marks
local scope_previewer = previewers.new_buffer_previewer({
    title = "Marks in Scope",
    define_preview = function(self, entry, status)
        local scope_name = entry.value
        local base_scope = quarker.get_scope()
        local marks_file = vim.fn.stdpath("data") .. "/quarker/" .. vim.fn.sha256(base_scope) .. "/" .. scope_name .. ".json"

        -- Read marks from file
        local marks = {}
        if vim.fn.filereadable(marks_file) == 1 then
            local file = io.open(marks_file, "r")
            if file then
                local content = file:read("*all")
                file:close()
                local success, data = pcall(vim.json.decode, content)
                if success and data and data.marks then
                    marks = data.marks
                end
            end
        end

        -- Prepare preview content
        local preview_lines = {}
        if #marks == 0 then
            table.insert(preview_lines, "No marks in this scope")
        else
            table.insert(preview_lines, string.format("Scope: %s (%d marks)", scope_name, #marks))
            table.insert(preview_lines, string.rep("─", 50))
            table.insert(preview_lines, "")

            for i, mark in ipairs(marks) do
                local icon, _ = get_filetype_icon(mark.name)
                table.insert(preview_lines, string.format("[%d] %s %s", i, icon or "", mark.path))
            end
        end

        -- Set preview content
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)

        -- Add syntax highlighting
        vim.api.nvim_buf_call(self.state.bufnr, function()
            vim.cmd("setlocal filetype=")
            -- Highlight the header
            vim.fn.matchadd("Title", "^Scope:.*")
            vim.fn.matchadd("Comment", "^─.*")
            -- Highlight index numbers
            vim.fn.matchadd("Number", "\\[\\d\\+\\]")
            -- Highlight "No marks" message
            vim.fn.matchadd("Comment", "No marks in this scope")
        end)
    end,
})

-- Scope manager telescope picker
function M.scope_manager()
    local scopes, active_scope = quarker.list_scopes()

    if #scopes == 0 then
        vim.notify("No scopes found", vim.log.levels.INFO)
        return
    end

    -- Prepare entries for telescope
    local entries = {}
    local default_selection = 1

    for i, scope_name in ipairs(scopes) do
        -- Find marks count for this scope
        local base_scope = quarker.get_scope()
        local marks_file = vim.fn.stdpath("data") .. "/quarker/" .. vim.fn.sha256(base_scope) .. "/" .. scope_name .. ".json"
        local marks_count = 0

        if vim.fn.filereadable(marks_file) == 1 then
            local file = io.open(marks_file, "r")
            if file then
                local content = file:read("*all")
                file:close()
                local success, data = pcall(vim.json.decode, content)
                if success and data and data.marks then
                    marks_count = #data.marks
                end
            end
        end

        -- Set default selection to active scope
        if scope_name == active_scope then
            default_selection = i
        end

        local is_active = scope_name == active_scope

        table.insert(entries, {
            value = scope_name,
            display = function(entry)
                local hl = {}
                local active_marker = entry.is_active and " [active]" or ""
                local display_str = string.format("%s (%d marks)%s", entry.scope_name, entry.marks_count, active_marker)

                -- Highlight active scope
                if entry.is_active then
                    table.insert(hl, { { 0, string.len(display_str) }, "String" })
                end

                return display_str, hl
            end,
            ordinal = scope_name,
            scope_name = scope_name,
            marks_count = marks_count,
            is_active = is_active
        })
    end

    pickers.new({}, {
        prompt_title = "Quarker Scopes",
        finder = finders.new_table {
            results = entries,
            entry_maker = function(entry)
                return entry
            end
        },
        sorter = conf.generic_sorter({}),
        previewer = scope_previewer,
        default_selection_index = default_selection,
        attach_mappings = function(prompt_bufnr, map)
            -- Default action: switch to scope
            actions.select_default:replace(switch_to_scope)

            -- Custom mappings
            -- <C-n> and <C-p> are preserved for Telescope navigation
            map("i", "<CR>", switch_to_scope)
            map("n", "<CR>", switch_to_scope)
            map("n", "n", create_new_scope)           -- Normal mode: 'n' to create new scope
            map("i", "<C-a>", create_new_scope)       -- Insert mode: Ctrl-a to create (add) new scope
            map("i", "<C-d>", delete_selected_scope)
            map("n", "dd", delete_selected_scope)
            map("n", "r", rename_selected_scope)

            return true
        end,
    }):find()
end

-- ============================================================================
-- Marks Picker
-- ============================================================================

-- Custom actions for the telescope picker
local function delete_mark(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        local index = selection.index
        if quarker.remove_mark(index) then
            -- Refresh the picker
            actions.close(prompt_bufnr)
            M.toggle_quarker()
        end
    end
end

local function clear_all_marks(prompt_bufnr)
    -- Ask for confirmation
    local choice = vim.fn.confirm("Clear all marks for current scope?", "&Yes\n&No", 2)
    if choice == 1 then
        quarker.clear_marks()
        actions.close(prompt_bufnr)
    end
end

local function navigate_to_mark(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        actions.close(prompt_bufnr)
        quarker.navigate(selection.index)
    end
end

local function move_mark_up(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        local index = selection.index
        if quarker.move_mark_up(index) then
            -- Refresh the picker and select the mark at its new position
            actions.close(prompt_bufnr)
            M.toggle_quarker(math.max(1, index - 1))
        end
    end
end

local function move_mark_down(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection then
        local index = selection.index
        if quarker.move_mark_down(index) then
            -- Refresh the picker and select the mark at its new position
            actions.close(prompt_bufnr)
            M.toggle_quarker(index + 1)
        end
    end
end

-- Main telescope picker for quarker
-- @param force_selection_index Optional index to force as the default selection
function M.toggle_quarker(force_selection_index)
    local marks = quarker.get_marks()
    local scope = quarker.get_scope()

    if #marks == 0 then
        vim.notify("No marks found in current scope", vim.log.levels.INFO)
        return
    end

    -- Get current buffer path for default selection
    local default_selection = force_selection_index or 1 -- Use forced index or default to first entry
    local current_relative_path = ""

    -- Only look for current buffer match if we're not forcing a selection
    if not force_selection_index then
        local current_buf_path = vim.api.nvim_buf_get_name(0)
        if current_buf_path ~= "" then
            if current_buf_path:sub(1, #scope) == scope then
                current_relative_path = current_buf_path:sub(#scope + 1)
                if current_relative_path:sub(1, 1) == "/" then
                    current_relative_path = current_relative_path:sub(2)
                end
            else
                current_relative_path = current_buf_path
            end
        end
    end

    -- Prepare entries for telescope
    local entries = {}
    for i, mark in ipairs(marks) do
        -- Check if this mark matches current buffer (compare relative paths)
        if not force_selection_index and current_relative_path ~= "" and mark.path == current_relative_path then
            default_selection = i
        end

        -- Create full path for telescope previewer
        local full_path = scope .. "/" .. mark.path

        table.insert(entries, {
            value = mark,
            display = function(entry)
                local hl = {}
                local filetype_icon, icon_hl = get_filetype_icon(entry.filename)
                local display_str = string.format("[%d] %s %s %s", entry.index, filetype_icon, entry.filename, entry.relative_path)

                local index_part = string.format("[%d] ", entry.index)
                local icon_part = filetype_icon .. " "
                local filename_start = string.len(index_part .. icon_part)
                local filename_end = filename_start + string.len(entry.filename)
                local path_start = filename_end + 1

                -- Highlight icon with its color
                if icon_hl and filetype_icon ~= "" then
                    table.insert(hl, { { string.len(index_part), string.len(index_part) + string.len(filetype_icon) }, icon_hl })
                end

                -- Highlight path in comment color
                table.insert(hl, { { path_start, string.len(display_str) }, "Comment" })

                return display_str, hl
            end,
            ordinal = string.format("[%d] %s", i, mark.name),
            index = i,
            path = full_path,  -- Use full path for telescope previewer
            relative_path = mark.path,  -- Store relative path for display
            filename = mark.name
        })
    end

    pickers.new({}, {
        prompt_title = string.format("Quarker Marks (%s)", vim.fn.fnamemodify(scope, ":t")),
        finder = finders.new_table {
            results = entries,
            entry_maker = function(entry)
                return entry
            end
        },
        sorter = conf.generic_sorter({}),
        previewer = conf.file_previewer({}),
        default_selection_index = default_selection,
        attach_mappings = function(prompt_bufnr, map)
            -- Default action: navigate to file
            actions.select_default:replace(navigate_to_mark)

            -- Custom mappings
            map("i", "<C-d>", delete_mark)
            map("n", "dd", delete_mark)
            map("i", "<CR>", navigate_to_mark)
            map("n", "<CR>", navigate_to_mark)
            map("i", "<C-k>", move_mark_up)
            map("n", "<C-k>", move_mark_up)
            map("i", "<C-j>", move_mark_down)
            map("n", "<C-j>", move_mark_down)
            map("i", "<C-x>", clear_all_marks)
            map("n", "<C-x>", clear_all_marks)

            return true
        end,
    }):find()
end

return M
