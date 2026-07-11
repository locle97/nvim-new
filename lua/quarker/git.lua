-- Git data layer for the Quarker panel's git tab: the only place that shells out.
local M = {}

local function scope_or_default(scope)
    return scope or require("quarker").get_scope()
end

-- Run git in `cwd` and return its raw stdout, or nil plus git's own message.
local function git(args, cwd)
    local cmd = { "git", "-C", cwd }
    vim.list_extend(cmd, args)

    local ok, result = pcall(function()
        return vim.system(cmd):wait()
    end)
    if not ok then
        return nil, "git is not available"
    end
    if result.code ~= 0 then
        local err = (result.stderr or ""):gsub("%s+$", "")
        return nil, err ~= "" and err or ("git " .. args[1] .. " failed")
    end
    return result.stdout or ""
end

local function entry(path, status)
    local dir = vim.fn.fnamemodify(path, ":h")
    return {
        path = path,
        name = vim.fn.fnamemodify(path, ":t"),
        dir = dir ~= "." and dir or "",
        status = status,
    }
end

-- Files git considers dirty, split the way git itself models them: a file with
-- both staged and unstaged edits appears in both lists.
-- @param scope string|nil Repository root; defaults to the active Quarker scope
-- @return table|nil { staged = {entry...}, unstaged = {entry...} }, string|nil error
function M.status(scope)
    local out, err = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all" }, scope_or_default(scope))
    if not out then
        return nil, err
    end

    -- --porcelain -z emits "XY <path>" per record, NUL-terminated, so paths with
    -- spaces or unicode need no unquoting. A rename adds the old path as its own
    -- trailing field; the record's own path is already the new one.
    local fields = vim.split(out, "\0", { plain = true })
    local staged, unstaged = {}, {}

    local i = 1
    while i <= #fields do
        local record = fields[i]
        i = i + 1

        if record ~= "" then
            local index_status = record:sub(1, 1)
            local worktree_status = record:sub(2, 2)
            local path = record:sub(4)

            if index_status == "R" or index_status == "C" then
                i = i + 1
            end

            if index_status == "?" then
                table.insert(unstaged, entry(path, "U"))
            else
                if index_status ~= " " then
                    table.insert(staged, entry(path, index_status))
                end
                if worktree_status ~= " " then
                    table.insert(unstaged, entry(path, worktree_status))
                end
            end
        end
    end

    return { staged = staged, unstaged = unstaged }
end

-- @return boolean ok, string|nil error
function M.stage(path, scope)
    local out, err = git({ "add", "--", path }, scope_or_default(scope))
    if not out then
        return false, err
    end
    return true
end

-- @return boolean ok, string|nil error
function M.unstage(path, scope)
    local out, err = git({ "restore", "--staged", "--", path }, scope_or_default(scope))
    if not out then
        return false, err
    end
    return true
end

return M
