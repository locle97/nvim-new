local M = {}

-- Storage for marked files per scope
local marks = {}

-- Storage for scope metadata per repository
local scope_metadata = {}

-- Cache for expensive operations
local cache = {
    scope = nil,
    scope_timestamp = 0,
    current_file = nil,
    current_file_timestamp = 0,
    statusline_result = "",
    statusline_timestamp = 0,
    marks_cache = {},
    marks_timestamp = 0,
    scope_metadata_cache = {},
    scope_metadata_timestamp = 0,
    context_cache = {},
    context_timestamp = 0
}

-- Default settings
local default_settings = {
    statusline = {
        icon = "󰇥",
        active = "[%s]",
        inactive = " %s ",
        include_icon = true,
    }
}

-- Get data directory for storing marks
local function get_data_dir()
    local data_dir = vim.fn.stdpath("data") .. "/quarker"
    vim.fn.mkdir(data_dir, "p")
    return data_dir
end

-- Get repository directory path
local function get_repo_dir(base_scope)
    local data_dir = get_data_dir()
    local scope_hash = vim.fn.sha256(base_scope)
    local repo_dir = data_dir .. "/" .. scope_hash
    vim.fn.mkdir(repo_dir, "p")
    return repo_dir
end

-- Get scope metadata file path
local function get_scope_metadata_file(base_scope)
    local repo_dir = get_repo_dir(base_scope)
    return repo_dir .. "/scopes.json"
end

-- Get marks file path for a scope
local function get_marks_file(base_scope, scope_name)
    local repo_dir = get_repo_dir(base_scope)
    return repo_dir .. "/" .. scope_name .. ".json"
end

-- Load scope metadata from disk
local function load_scope_metadata(base_scope)
    local metadata_file = get_scope_metadata_file(base_scope)

    if vim.fn.filereadable(metadata_file) == 0 then
        -- Return default metadata
        return {
            active_scope = "default",
            scopes = { "default" }
        }
    end

    local file = io.open(metadata_file, "r")
    if not file then
        return {
            active_scope = "default",
            scopes = { "default" }
        }
    end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then
        return {
            active_scope = "default",
            scopes = { "default" }
        }
    end

    local success, data = pcall(vim.json.decode, content)
    if not success or not data then
        return {
            active_scope = "default",
            scopes = { "default" }
        }
    end

    return data
end

-- Save scope metadata to disk
local function save_scope_metadata(base_scope, metadata)
    local metadata_file = get_scope_metadata_file(base_scope)

    local success, encoded = pcall(vim.json.encode, metadata)
    if not success then
        vim.notify("Failed to encode scope metadata", vim.log.levels.ERROR)
        return false
    end

    local file = io.open(metadata_file, "w")
    if file then
        file:write(encoded)
        file:close()
        -- Invalidate cache
        cache.scope_metadata_timestamp = 0
        return true
    else
        vim.notify("Failed to save scope metadata to " .. metadata_file, vim.log.levels.ERROR)
        return false
    end
end

-- Get scope metadata with caching
local function get_scope_metadata(base_scope)
    local now = vim.loop.hrtime()

    -- Cache for 500ms
    if scope_metadata[base_scope] and (now - cache.scope_metadata_timestamp) < 5e8 then
        return scope_metadata[base_scope]
    end

    local metadata = load_scope_metadata(base_scope)
    scope_metadata[base_scope] = metadata
    cache.scope_metadata_timestamp = now

    return metadata
end

-- Migrate old marks format to new format (backwards compatibility)
-- Forward declare save_marks for use in migration
local save_marks

local function migrate_old_marks(base_scope, scope_name)
    -- Only migrate to "default" scope
    if scope_name ~= "default" then
        return {}
    end

    local old_marks_file = get_data_dir() .. "/" .. vim.fn.sha256(base_scope) .. ".json"

    if vim.fn.filereadable(old_marks_file) == 0 then
        return {}
    end

    local file = io.open(old_marks_file, "r")
    if not file then
        return {}
    end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then
        return {}
    end

    local success, data = pcall(vim.json.decode, content)
    if not success or not data or not data.marks then
        return {}
    end

    -- Save to new format
    local full_scope = base_scope .. ":default"
    marks[full_scope] = data.marks
    save_marks(base_scope, "default")

    -- Delete old file
    os.remove(old_marks_file)

    vim.notify("Migrated marks to new scope format", vim.log.levels.INFO)

    return data.marks
end

-- Save marks for a scope to disk
save_marks = function(base_scope, scope_name)
    local full_scope = base_scope .. ":" .. scope_name
    local scope_marks = marks[full_scope]
    if not scope_marks then
        return
    end

    local marks_file = get_marks_file(base_scope, scope_name)
    local data = {
        scope = base_scope,
        scope_name = scope_name,
        marks = scope_marks,
        timestamp = os.time()
    }

    local success, encoded = pcall(vim.json.encode, data)
    if not success then
        vim.notify("Failed to encode marks data", vim.log.levels.ERROR)
        return
    end

    local file = io.open(marks_file, "w")
    if file then
        file:write(encoded)
        file:close()
        -- Invalidate caches when marks change
        cache.statusline_timestamp = 0
        cache.marks_timestamp = 0
    else
        vim.notify("Failed to save marks to " .. marks_file, vim.log.levels.ERROR)
    end
end

-- Load marks for a scope from disk
local function load_marks(base_scope, scope_name)
    local marks_file = get_marks_file(base_scope, scope_name)

    if vim.fn.filereadable(marks_file) == 0 then
        -- Try to migrate from old format
        return migrate_old_marks(base_scope, scope_name)
    end

    local file = io.open(marks_file, "r")
    if not file then
        return {}
    end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then
        return {}
    end

    local success, data = pcall(vim.json.decode, content)
    if not success or not data or not data.marks then
        vim.notify("Failed to decode marks file: " .. marks_file, vim.log.levels.WARN)
        return {}
    end

    return data.marks
end

-- Get the base scope (git root or CWD) with caching
local function get_base_scope()
    local now = vim.loop.hrtime()
    -- Cache scope for 5 seconds to reduce git command calls
    if cache.scope and (now - cache.scope_timestamp) < 5e9 then
        return cache.scope
    end

    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    local scope
    if vim.v.shell_error == 0 and git_root and git_root ~= "" then
        scope = git_root
    else
        scope = vim.fn.getcwd()
    end

    cache.scope = scope
    cache.scope_timestamp = now
    return scope
end

-- Get the active scope name for current repository
local function get_active_scope_name()
    local base_scope = get_base_scope()
    local metadata = get_scope_metadata(base_scope)
    return metadata.active_scope
end

-- Get full scope identifier (base_scope:scope_name)
local function get_full_scope()
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    return base_scope .. ":" .. scope_name
end

-- Get the current scope's marks
local function get_marks()
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    local full_scope = base_scope .. ":" .. scope_name

    if not marks[full_scope] then
        marks[full_scope] = load_marks(base_scope, scope_name)
    end
    return marks[full_scope]
end

-- Get relative path from scope
local function get_relative_path(filepath, scope)
    if filepath:sub(1, #scope) == scope then
        local relative = filepath:sub(#scope + 1)
        if relative:sub(1, 1) == "/" then
            relative = relative:sub(2)
        end
        return relative
    end
    return filepath
end

-- Mark current file
function M.mark()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to mark", vim.log.levels.WARN)
        return
    end

    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    local relative_path = get_relative_path(filepath, base_scope)
    local scope_marks = get_marks()

    -- Check if already marked
    for i, mark in ipairs(scope_marks) do
        if mark.path == relative_path then
            vim.notify(string.format("File already marked at position %d in scope '%s'", i, scope_name), vim.log.levels.INFO)
            return
        end
    end

    -- Add new mark
    table.insert(scope_marks, {
        path = relative_path,
        full_path = filepath,
        name = vim.fn.fnamemodify(filepath, ":t")
    })

    vim.notify(string.format("Marked file at position %d in scope '%s': %s", #scope_marks, scope_name, relative_path), vim.log.levels.INFO)
    save_marks(base_scope, scope_name)
end

-- Unmark current file
function M.unmark()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to unmark", vim.log.levels.WARN)
        return
    end

    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    local relative_path = get_relative_path(filepath, base_scope)
    local scope_marks = get_marks()

    for i, mark in ipairs(scope_marks) do
        if mark.path == relative_path then
            table.remove(scope_marks, i)
            vim.notify(string.format("Unmarked file from scope '%s': %s", scope_name, relative_path), vim.log.levels.INFO)
            save_marks(base_scope, scope_name)
            return
        end
    end

    vim.notify("File is not marked in current scope", vim.log.levels.WARN)
end

-- Navigate to marked file by index
function M.navigate(index)
    local scope_marks = get_marks()

    if index < 1 or index > #scope_marks then
        vim.notify(string.format("Invalid index %d. Available marks: 1-%d", index, #scope_marks), vim.log.levels.WARN)
        return
    end

    local mark = scope_marks[index]
    local base_scope = get_base_scope()
    local full_path = base_scope .. "/" .. mark.path

    -- Check if file exists
    if vim.fn.filereadable(full_path) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(full_path))
    else
        vim.notify(string.format("File not found: %s", full_path), vim.log.levels.ERROR)
    end
end

-- Get all marks for current scope
function M.get_marks()
    return get_marks()
end

-- Set marks for current scope (used by UI to sync buffer changes)
function M.set_marks(new_marks)
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    local full_scope = base_scope .. ":" .. scope_name

    marks[full_scope] = new_marks
    save_marks(base_scope, scope_name)
end

-- Get current base scope (repository path)
function M.get_scope()
    return get_base_scope()
end

-- Get active scope name
function M.get_active_scope_name()
    return get_active_scope_name()
end

-- Remove mark by index
function M.remove_mark(index)
    local scope_marks = get_marks()

    if index < 1 or index > #scope_marks then
        vim.notify(string.format("Invalid index %d", index), vim.log.levels.WARN)
        return false
    end

    local removed = table.remove(scope_marks, index)
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    vim.notify(string.format("Removed mark from scope '%s': %s", scope_name, removed.path), vim.log.levels.INFO)
    save_marks(base_scope, scope_name)
    return true
end

-- Toggle mark for current file
function M.toggle()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to toggle mark", vim.log.levels.WARN)
        return
    end

    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    local relative_path = get_relative_path(filepath, base_scope)
    local scope_marks = get_marks()

    -- Check if already marked
    for i, mark in ipairs(scope_marks) do
        if mark.path == relative_path then
            -- Unmark if already marked
            table.remove(scope_marks, i)
            vim.notify(string.format("Unmarked file from scope '%s': %s", scope_name, relative_path), vim.log.levels.INFO)
            save_marks(base_scope, scope_name)
            return
        end
    end

    -- Mark if not already marked
    table.insert(scope_marks, {
        path = relative_path,
        full_path = filepath,
        name = vim.fn.fnamemodify(filepath, ":t")
    })

    vim.notify(string.format("Marked file at position %d in scope '%s': %s", #scope_marks, scope_name, relative_path), vim.log.levels.INFO)
    save_marks(base_scope, scope_name)
end

-- Move mark up by one position
function M.move_mark_up(index)
    local scope_marks = get_marks()

    if index < 2 or index > #scope_marks then
        return false
    end

    -- Swap with previous mark
    scope_marks[index], scope_marks[index - 1] = scope_marks[index - 1], scope_marks[index]
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    save_marks(base_scope, scope_name)
    return true
end

-- Move mark down by one position
function M.move_mark_down(index)
    local scope_marks = get_marks()

    if index < 1 or index >= #scope_marks then
        return false
    end

    -- Swap with next mark
    scope_marks[index], scope_marks[index + 1] = scope_marks[index + 1], scope_marks[index]
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    save_marks(base_scope, scope_name)
    return true
end

-- Clear all marks for current scope
function M.clear_marks()
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    local full_scope = base_scope .. ":" .. scope_name
    marks[full_scope] = {}
    save_marks(base_scope, scope_name)
    vim.notify(string.format("Cleared all marks for scope '%s'", scope_name), vim.log.levels.INFO)
end

-- Get statusline component showing current position in marked files
function M.statusline()
    local now = vim.loop.hrtime()
    local current_file = vim.fn.expand("%:p")

    -- Cache statusline result for 200ms to avoid excessive computation during rapid navigation
    if cache.statusline_result and
       cache.current_file == current_file and
       (now - cache.statusline_timestamp) < 2e8 then
        return cache.statusline_result
    end

    -- Use cached marks if available and recent (within 500ms)
    local scope_marks
    if cache.marks_cache and (now - cache.marks_timestamp) < 5e8 then
        scope_marks = cache.marks_cache
    else
        scope_marks = get_marks()
        cache.marks_cache = scope_marks
        cache.marks_timestamp = now
    end

    local count = #scope_marks

    if count == 0 then
        cache.statusline_result = ""
        cache.current_file = current_file
        cache.statusline_timestamp = now
        return ""
    end

    if current_file == "" then
        cache.statusline_result = ""
        cache.current_file = current_file
        cache.statusline_timestamp = now
        return ""
    end

    -- Get scope info
    local base_scope = cache.scope or get_base_scope()
    local scope_name = get_active_scope_name()
    local relative_path = get_relative_path(current_file, base_scope)
    local current_index = nil

    -- Find current file's index in marks
    for i, mark in ipairs(scope_marks) do
        if mark.path == relative_path then
            current_index = i
            break
        end
    end

    local settings = default_settings.statusline
    local icon = settings.include_icon and settings.icon or ""
    local result

    if current_index then
        -- Current file is marked - show position and scope name
        result = string.format(" %s [%d] of [%d] (%s)", icon, current_index, count, scope_name)
    else
        -- Current file is not marked - show dash and scope name
        result = string.format(" %s [-] of [%d] (%s)", icon, count, scope_name)
    end

    -- Cache the result
    cache.statusline_result = result
    cache.current_file = current_file
    cache.statusline_timestamp = now

    return result
end

-- ============================================================================
-- Scope Management Functions
-- ============================================================================

-- List all scopes for current repository
function M.list_scopes()
    local base_scope = get_base_scope()
    local metadata = get_scope_metadata(base_scope)
    return metadata.scopes, metadata.active_scope
end

-- Create a new scope
function M.create_scope(scope_name)
    if not scope_name or scope_name == "" then
        vim.notify("Scope name cannot be empty", vim.log.levels.ERROR)
        return false
    end

    -- Validate scope name (alphanumeric, dash, underscore only)
    if not scope_name:match("^[a-zA-Z0-9_-]+$") then
        vim.notify("Scope name can only contain letters, numbers, dashes, and underscores", vim.log.levels.ERROR)
        return false
    end

    local base_scope = get_base_scope()
    local metadata = get_scope_metadata(base_scope)

    -- Check if scope already exists
    for _, name in ipairs(metadata.scopes) do
        if name == scope_name then
            vim.notify(string.format("Scope '%s' already exists", scope_name), vim.log.levels.WARN)
            return false
        end
    end

    -- Add scope to metadata
    table.insert(metadata.scopes, scope_name)

    -- Save metadata
    if save_scope_metadata(base_scope, metadata) then
        vim.notify(string.format("Created scope '%s'", scope_name), vim.log.levels.INFO)
        return true
    end

    return false
end

-- Switch to a different scope
function M.switch_scope(scope_name)
    if not scope_name or scope_name == "" then
        vim.notify("Scope name cannot be empty", vim.log.levels.ERROR)
        return false
    end

    local base_scope = get_base_scope()
    local metadata = get_scope_metadata(base_scope)

    -- Check if scope exists
    local scope_exists = false
    for _, name in ipairs(metadata.scopes) do
        if name == scope_name then
            scope_exists = true
            break
        end
    end

    if not scope_exists then
        vim.notify(string.format("Scope '%s' does not exist", scope_name), vim.log.levels.ERROR)
        return false
    end

    -- Switch active scope
    metadata.active_scope = scope_name

    -- Save metadata and invalidate caches
    if save_scope_metadata(base_scope, metadata) then
        cache.statusline_timestamp = 0
        cache.marks_timestamp = 0
        cache.scope_metadata_timestamp = 0
        scope_metadata[base_scope] = metadata

        vim.notify(string.format("Switched to scope '%s'", scope_name), vim.log.levels.INFO)
        return true
    end

    return false
end

-- Delete a scope
function M.delete_scope(scope_name)
    if not scope_name or scope_name == "" then
        vim.notify("Scope name cannot be empty", vim.log.levels.ERROR)
        return false
    end

    -- Cannot delete default scope
    if scope_name == "default" then
        vim.notify("Cannot delete the default scope", vim.log.levels.ERROR)
        return false
    end

    local base_scope = get_base_scope()
    local metadata = get_scope_metadata(base_scope)

    -- Check if scope exists
    local scope_index = nil
    for i, name in ipairs(metadata.scopes) do
        if name == scope_name then
            scope_index = i
            break
        end
    end

    if not scope_index then
        vim.notify(string.format("Scope '%s' does not exist", scope_name), vim.log.levels.ERROR)
        return false
    end

    -- Remove scope from metadata
    table.remove(metadata.scopes, scope_index)

    -- If deleting active scope, switch to default
    if metadata.active_scope == scope_name then
        metadata.active_scope = "default"
    end

    -- Delete marks file
    local marks_file = get_marks_file(base_scope, scope_name)
    if vim.fn.filereadable(marks_file) == 1 then
        os.remove(marks_file)
    end

    -- Delete context file
    local context = require("quarker.context")
    context._delete_context(base_scope, scope_name)

    -- Clear marks from memory
    local full_scope = base_scope .. ":" .. scope_name
    marks[full_scope] = nil

    -- Save metadata
    if save_scope_metadata(base_scope, metadata) then
        cache.statusline_timestamp = 0
        cache.marks_timestamp = 0
        cache.scope_metadata_timestamp = 0
        scope_metadata[base_scope] = metadata

        vim.notify(string.format("Deleted scope '%s'", scope_name), vim.log.levels.INFO)
        return true
    end

    return false
end

-- Rename a scope
function M.rename_scope(old_name, new_name)
    if not old_name or old_name == "" or not new_name or new_name == "" then
        vim.notify("Scope names cannot be empty", vim.log.levels.ERROR)
        return false
    end

    -- Cannot rename default scope
    if old_name == "default" then
        vim.notify("Cannot rename the default scope", vim.log.levels.ERROR)
        return false
    end

    -- Validate new scope name
    if not new_name:match("^[a-zA-Z0-9_-]+$") then
        vim.notify("Scope name can only contain letters, numbers, dashes, and underscores", vim.log.levels.ERROR)
        return false
    end

    local base_scope = get_base_scope()
    local metadata = get_scope_metadata(base_scope)

    -- Check if old scope exists
    local scope_index = nil
    for i, name in ipairs(metadata.scopes) do
        if name == old_name then
            scope_index = i
            break
        end
    end

    if not scope_index then
        vim.notify(string.format("Scope '%s' does not exist", old_name), vim.log.levels.ERROR)
        return false
    end

    -- Check if new name already exists
    for _, name in ipairs(metadata.scopes) do
        if name == new_name then
            vim.notify(string.format("Scope '%s' already exists", new_name), vim.log.levels.WARN)
            return false
        end
    end

    -- Update metadata
    metadata.scopes[scope_index] = new_name
    if metadata.active_scope == old_name then
        metadata.active_scope = new_name
    end

    -- Rename marks file
    local old_marks_file = get_marks_file(base_scope, old_name)
    local new_marks_file = get_marks_file(base_scope, new_name)

    if vim.fn.filereadable(old_marks_file) == 1 then
        os.rename(old_marks_file, new_marks_file)
    end

    -- Rename context file
    local context = require("quarker.context")
    context._rename_context(base_scope, old_name, new_name)

    -- Update marks in memory
    local old_full_scope = base_scope .. ":" .. old_name
    local new_full_scope = base_scope .. ":" .. new_name
    if marks[old_full_scope] then
        marks[new_full_scope] = marks[old_full_scope]
        marks[old_full_scope] = nil
    end

    -- Save metadata
    if save_scope_metadata(base_scope, metadata) then
        cache.statusline_timestamp = 0
        cache.marks_timestamp = 0
        cache.scope_metadata_timestamp = 0
        scope_metadata[base_scope] = metadata

        vim.notify(string.format("Renamed scope '%s' to '%s'", old_name, new_name), vim.log.levels.INFO)
        return true
    end

    return false
end

-- ============================================================================
-- Command Interface
-- ============================================================================

-- Setup user commands
function M.setup_commands()
    vim.api.nvim_create_user_command("Quarker", function(opts)
        local args = vim.split(opts.args, "%s+")
        local subcommand = args[1]

        if not subcommand then
            vim.notify("Usage: :Quarker <subcommand> [args]", vim.log.levels.INFO)
            return
        end

        -- Scope management commands
        if subcommand == "scope" then
            local scope_action = args[2]

            if not scope_action then
                vim.notify("Usage: :Quarker scope <create|list|switch|delete|rename|current>", vim.log.levels.INFO)
                return
            end

            if scope_action == "create" then
                local scope_name = args[3]
                if not scope_name then
                    vim.ui.input({ prompt = "New scope name: " }, function(input)
                        if input and input ~= "" then
                            M.create_scope(input)
                        end
                    end)
                else
                    M.create_scope(scope_name)
                end

            elseif scope_action == "list" then
                local scopes, active = M.list_scopes()
                local base_scope = get_base_scope()

                vim.notify("Available scopes:", vim.log.levels.INFO)
                for _, scope_name in ipairs(scopes) do
                    local marks_file = get_marks_file(base_scope, scope_name)
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

                    local marker = scope_name == active and " [active]" or ""
                    print(string.format("  - %s (%d marks)%s", scope_name, marks_count, marker))
                end

            elseif scope_action == "switch" then
                local scope_name = args[3]
                if not scope_name then
                    -- Show picker
                    require("quarker.telescope").scope_manager()
                else
                    M.switch_scope(scope_name)
                end

            elseif scope_action == "delete" then
                local scope_name = args[3]
                if not scope_name then
                    vim.notify("Usage: :Quarker scope delete <scope_name>", vim.log.levels.ERROR)
                    return
                end

                local choice = vim.fn.confirm(string.format("Delete scope '%s'?", scope_name), "&Yes\n&No", 2)
                if choice == 1 then
                    M.delete_scope(scope_name)
                end

            elseif scope_action == "rename" then
                local old_name = args[3]
                local new_name = args[4]

                if not old_name then
                    vim.notify("Usage: :Quarker scope rename <old_name> <new_name>", vim.log.levels.ERROR)
                    return
                end

                if not new_name then
                    vim.ui.input({ prompt = string.format("Rename '%s' to: ", old_name) }, function(input)
                        if input and input ~= "" then
                            M.rename_scope(old_name, input)
                        end
                    end)
                else
                    M.rename_scope(old_name, new_name)
                end

            elseif scope_action == "current" then
                local scope_name = get_active_scope_name()
                local scope_marks = get_marks()
                vim.notify(string.format("Current scope: %s (%d marks)", scope_name, #scope_marks), vim.log.levels.INFO)

            else
                vim.notify("Unknown scope action: " .. scope_action, vim.log.levels.ERROR)
                vim.notify("Available actions: create, list, switch, delete, rename, current", vim.log.levels.INFO)
            end

        -- Context commands
        elseif subcommand == "context" then
            local context_action = args[2]

            if not context_action then
                -- Show context UI
                require("quarker.ui").show_context()
            elseif context_action == "export" then
                require("quarker.context").export()
            else
                vim.notify("Unknown context action: " .. context_action, vim.log.levels.ERROR)
                vim.notify("Available: export (or no args to edit)", vim.log.levels.INFO)
            end

        -- AI commands
        elseif subcommand == "ai" then
            local ai_action = args[2]
            local ai_module = require("quarker.ai")

            if not ai_action then
                ai_module.status()
            elseif ai_action == "generate" then
                -- Collect remaining args as seed prompt
                local seed = table.concat(vim.list_slice(args, 3), " ")
                ai_module.generate_context(seed ~= "" and seed or nil)
            elseif ai_action == "feature" then
                local name = args[3]
                if not name then
                    vim.notify("Usage: :Quarker ai feature <name>", vim.log.levels.ERROR)
                else
                    ai_module.generate_feature_note(name)
                end
            elseif ai_action == "refresh" then
                local since = args[3] or "HEAD~1"
                ai_module.refresh_context(since)
            elseif ai_action == "commit" then
                ai_module.generate_commit_msg()
            elseif ai_action == "status" then
                ai_module.status()
            else
                vim.notify("Unknown ai action: " .. ai_action, vim.log.levels.ERROR)
                vim.notify("Available: generate, feature, refresh, commit, status", vim.log.levels.INFO)
            end

        -- Telescope pickers
        elseif subcommand == "scopes" then
            require("quarker.telescope").scope_manager()
        elseif subcommand == "marks" then
            require("quarker.telescope").toggle_quarker()

        -- Mark management commands
        elseif subcommand == "mark" then
            M.mark()
        elseif subcommand == "unmark" then
            M.unmark()
        elseif subcommand == "toggle" then
            M.toggle()
        elseif subcommand == "clear" then
            local choice = vim.fn.confirm("Clear all marks for current scope?", "&Yes\n&No", 2)
            if choice == 1 then
                M.clear_marks()
            end
        elseif subcommand == "list" then
            require("quarker.telescope").toggle_quarker()
        elseif subcommand == "navigate" then
            local index = tonumber(args[2])
            if index then
                M.navigate(index)
            else
                vim.notify("Usage: :Quarker navigate <index>", vim.log.levels.ERROR)
            end

        else
            vim.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
            vim.notify("Available commands: scopes, marks, scope, context, ai, mark, unmark, toggle, clear, list, navigate", vim.log.levels.INFO)
        end
    end, {
        nargs = "*",
        complete = function(ArgLead, CmdLine, CursorPos)
            local args = vim.split(CmdLine, "%s+")
            local num_args = #args

            -- Complete first argument (subcommands)
            if num_args == 2 then
                local subcommands = { "scopes", "marks", "scope", "context", "ai", "mark", "unmark", "toggle", "clear", "list", "navigate" }
                return vim.tbl_filter(function(cmd)
                    return cmd:find(ArgLead, 1, true) == 1
                end, subcommands)
            end

            -- Complete scope subcommands
            if num_args == 3 and args[2] == "scope" then
                local scope_actions = { "create", "list", "switch", "delete", "rename", "current" }
                return vim.tbl_filter(function(action)
                    return action:find(ArgLead, 1, true) == 1
                end, scope_actions)
            end

            -- Complete context subcommands
            if num_args == 3 and args[2] == "context" then
                local context_actions = { "export" }
                return vim.tbl_filter(function(action)
                    return action:find(ArgLead, 1, true) == 1
                end, context_actions)
            end

            -- Complete ai subcommands
            if num_args == 3 and args[2] == "ai" then
                local ai_actions = { "generate", "feature", "refresh", "commit", "status" }
                return vim.tbl_filter(function(action)
                    return action:find(ArgLead, 1, true) == 1
                end, ai_actions)
            end

            -- Complete scope names for switch, delete, rename
            if num_args >= 4 and args[2] == "scope" and (args[3] == "switch" or args[3] == "delete" or args[3] == "rename") then
                local scopes, _ = M.list_scopes()
                return vim.tbl_filter(function(scope)
                    return scope:find(ArgLead, 1, true) == 1
                end, scopes)
            end

            return {}
        end,
        desc = "Quarker file mark and scope management"
    })
end

-- UI functions
M.show_marks_ui = function()
    require("quarker.ui").show_marks()
end

M.show_scopes_ui = function()
    require("quarker.ui").show_scopes()
end

M.show_context_ui = function()
    require("quarker.ui").show_context()
end

-- Module re-exports for convenience
M.context = require("quarker.context")
M.ai = require("quarker.ai")

-- Auto-setup commands when module is loaded
M.setup_commands()

return M
