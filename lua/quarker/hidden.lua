-- Files the Git Changes tab should stop listing.
--
-- Not a git concept: a hidden file stays dirty, stageable and searchable. It is a
-- view filter for the files that can neither be committed nor .gitignored (which
-- would make them unsearchable), and so sit in `git status` forever.
--
-- One set of repo-relative paths per repository, persisted next to that repo's
-- marks and scopes.
local M = {}

-- base_scope -> { [path] = true }. Loaded on first use, written through on change.
local cache = {}

local function scope_or_default(scope)
    return scope or require("quarker").get_scope()
end

local function hidden_file(base_scope)
    return require("quarker").get_repo_dir(base_scope) .. "/hidden.json"
end

-- A missing, unreadable or corrupt file reads as "nothing is hidden": a bad state
-- file must not take the git tab down with it.
local function load(base_scope)
    local path = hidden_file(base_scope)
    local set = {}

    if vim.fn.filereadable(path) == 0 then
        return set
    end

    local file = io.open(path, "r")
    if not file then
        return set
    end

    local content = file:read("*all")
    file:close()

    local ok, data = pcall(vim.json.decode, content or "")
    if not ok or type(data) ~= "table" or type(data.paths) ~= "table" then
        return set
    end

    for _, entry in ipairs(data.paths) do
        if type(entry) == "string" then
            set[entry] = true
        end
    end

    return set
end

local function get(base_scope)
    if not cache[base_scope] then
        cache[base_scope] = load(base_scope)
    end
    return cache[base_scope]
end

-- An object rather than a bare array, so a later `globs` key needs no migration.
local function save(base_scope)
    local paths = M.list(base_scope)
    local ok, encoded = pcall(vim.json.encode, { paths = paths })
    if not ok then
        vim.notify("Failed to encode hidden files", vim.log.levels.ERROR)
        return false
    end

    local path = hidden_file(base_scope)
    local file = io.open(path, "w")
    if not file then
        vim.notify("Failed to save hidden files to " .. path, vim.log.levels.ERROR)
        return false
    end

    file:write(encoded)
    file:close()
    return true
end

-- @param path string Repo-relative path, as git.status() reports it
function M.is_hidden(path, scope)
    return get(scope_or_default(scope))[path] == true
end

function M.hide(path, scope)
    local base_scope = scope_or_default(scope)
    get(base_scope)[path] = true
    save(base_scope)
end

function M.unhide(path, scope)
    local base_scope = scope_or_default(scope)
    get(base_scope)[path] = nil
    save(base_scope)
end

-- @return table Hidden paths, sorted
function M.list(scope)
    local paths = vim.tbl_keys(get(scope_or_default(scope)))
    table.sort(paths)
    return paths
end

-- Drop the in-memory copy so the next read comes from disk. Tests only.
function M.invalidate(scope)
    cache[scope_or_default(scope)] = nil
end

return M
