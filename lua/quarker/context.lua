local M = {}

-- ============================================================================
-- Storage Functions
-- ============================================================================

local function get_data_dir()
    local data_dir = vim.fn.stdpath("data") .. "/quarker"
    vim.fn.mkdir(data_dir, "p")
    return data_dir
end

local function get_repo_dir(base_scope)
    local data_dir = get_data_dir()
    local scope_hash = vim.fn.sha256(base_scope)
    local repo_dir = data_dir .. "/" .. scope_hash
    vim.fn.mkdir(repo_dir, "p")
    return repo_dir
end

local function get_context_file(base_scope, scope_name)
    local repo_dir = get_repo_dir(base_scope)
    return repo_dir .. "/" .. scope_name .. ".context.md"
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

local function get_quarker()
    return require("quarker")
end

local function get_base_scope()
    return get_quarker().get_scope()
end

local function get_active_scope_name()
    return get_quarker().get_active_scope_name()
end

-- ============================================================================
-- Public API
-- ============================================================================

-- Get context file path for current scope
function M.get_context_path()
    local base_scope = get_base_scope()
    local scope_name = get_active_scope_name()
    return get_context_file(base_scope, scope_name)
end

-- Read context content
function M.get_content()
    local filepath = M.get_context_path()
    if vim.fn.filereadable(filepath) == 0 then
        return ""
    end

    local file = io.open(filepath, "r")
    if not file then
        return ""
    end

    local content = file:read("*all")
    file:close()
    return content or ""
end

-- Write context content
function M.set_content(content)
    local filepath = M.get_context_path()

    local file = io.open(filepath, "w")
    if file then
        file:write(content or "")
        file:close()
        return true
    end
    return false
end

-- Export to clipboard
function M.export()
    local content = M.get_content()
    if content == "" then
        vim.notify("Context is empty", vim.log.levels.INFO)
        return
    end

    vim.fn.setreg("+", content)
    vim.fn.setreg("*", content)
    vim.notify("Context exported to clipboard", vim.log.levels.INFO)
end

-- ============================================================================
-- Internal API - For use by quarker/init.lua
-- ============================================================================

function M._delete_context(base_scope, scope_name)
    local filepath = get_context_file(base_scope, scope_name)
    if vim.fn.filereadable(filepath) == 1 then
        os.remove(filepath)
    end
end

function M._rename_context(base_scope, old_name, new_name)
    local old_file = get_context_file(base_scope, old_name)
    local new_file = get_context_file(base_scope, new_name)

    if vim.fn.filereadable(old_file) == 1 then
        os.rename(old_file, new_file)
    end
end

return M
