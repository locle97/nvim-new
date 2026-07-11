-- Run from repo root:
--   XDG_DATA_HOME="$(mktemp -d)" nvim -l tests/quarker/git_status_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg)
    io.stderr:write("FAIL: " .. msg .. "\n")
    os.exit(1)
end

local function run(cmd, cwd)
    local out = vim.fn.systemlist({ "git", "-C", cwd, unpack(cmd) })
    if vim.v.shell_error ~= 0 then
        fail("git " .. table.concat(cmd, " ") .. " failed: " .. table.concat(out, "\n"))
    end
    return out
end

local function write_file(path, contents)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = io.open(path, "w")
    fd:write(contents)
    fd:close()
end

-- Index the returned entries by path so assertions do not depend on git's ordering.
local function by_path(entries)
    local map = {}
    for _, entry in ipairs(entries) do
        map[entry.path] = entry
    end
    return map
end

local function expect_entry(map, path, status, name, dir)
    local entry = map[path]
    if not entry then
        fail("expected an entry for '" .. path .. "'")
    end
    if entry.status ~= status then
        fail(string.format("expected status '%s' for '%s', got '%s'", status, path, tostring(entry.status)))
    end
    if entry.name ~= name then
        fail(string.format("expected name '%s' for '%s', got '%s'", name, path, tostring(entry.name)))
    end
    if entry.dir ~= dir then
        fail(string.format("expected dir '%s' for '%s', got '%s'", dir, path, tostring(entry.dir)))
    end
end

-- A repo with one of every state the git tab has to render.
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
run({ "init", "-q", "-b", "main" }, tmp)
run({ "config", "user.email", "test@example.com" }, tmp)
run({ "config", "user.name", "Test" }, tmp)

-- Contents are distinct per file: identical contents make git's rename detection
-- pair unrelated adds and deletes, which is not what any of these cases are about.
write_file(tmp .. "/lua/utils.lua", "return { utils = true }\n")
write_file(tmp .. "/keep.lua", "return { keep = true }\n")
write_file(tmp .. "/gone.lua", "return { gone = true }\n")
write_file(tmp .. "/both.lua", "return { both = true }\n")
run({ "add", "-A" }, tmp)
run({ "commit", "-qm", "init" }, tmp)

write_file(tmp .. "/lua/utils.lua", "return { utils = true, changed = true }\n") -- unstaged M
write_file(tmp .. "/new file.lua", "return { spaced = true }\n") -- untracked, path with a space
vim.fn.delete(tmp .. "/gone.lua") -- unstaged D
write_file(tmp .. "/staged.lua", "return { staged = true }\n")
run({ "add", "staged.lua" }, tmp) -- staged A
write_file(tmp .. "/both.lua", "return { both = true, staged = true }\n")
run({ "add", "both.lua" }, tmp)
write_file(tmp .. "/both.lua", "return { both = true, staged = true, then_edited = true }\n") -- staged M + unstaged M

local git = require("quarker.git")

local status, err = git.status(tmp)
if not status then
    fail("expected status() to succeed, got error: " .. tostring(err))
end

local unstaged = by_path(status.unstaged)
expect_entry(unstaged, "lua/utils.lua", "M", "utils.lua", "lua")
expect_entry(unstaged, "new file.lua", "U", "new file.lua", "")
expect_entry(unstaged, "gone.lua", "D", "gone.lua", "")
expect_entry(unstaged, "both.lua", "M", "both.lua", "")
if #status.unstaged ~= 4 then
    fail("expected 4 unstaged entries, got " .. #status.unstaged)
end

local staged = by_path(status.staged)
expect_entry(staged, "staged.lua", "A", "staged.lua", "")
expect_entry(staged, "both.lua", "M", "both.lua", "")
if #status.staged ~= 2 then
    fail("expected 2 staged entries, got " .. #status.staged)
end

-- Renames report the new path.
run({ "mv", "keep.lua", "renamed.lua" }, tmp)
status = git.status(tmp)
expect_entry(by_path(status.staged), "renamed.lua", "R", "renamed.lua", "")

-- stage/unstage round-trip, including a path with a space.
local ok, stage_err = git.stage("new file.lua", tmp)
if not ok then
    fail("expected stage() to succeed, got error: " .. tostring(stage_err))
end
status = git.status(tmp)
expect_entry(by_path(status.staged), "new file.lua", "A", "new file.lua", "")
if by_path(status.unstaged)["new file.lua"] then
    fail("expected 'new file.lua' to leave the unstaged list once staged")
end

ok, stage_err = git.unstage("new file.lua", tmp)
if not ok then
    fail("expected unstage() to succeed, got error: " .. tostring(stage_err))
end
status = git.status(tmp)
expect_entry(by_path(status.unstaged), "new file.lua", "U", "new file.lua", "")
if by_path(status.staged)["new file.lua"] then
    fail("expected 'new file.lua' to leave the staged list once unstaged")
end

-- Outside a repo, status() reports the failure instead of pretending the tree is clean.
local not_repo = vim.fn.tempname()
vim.fn.mkdir(not_repo, "p")
local none, none_err = git.status(not_repo)
if none ~= nil then
    fail("expected status() to return nil outside a git repository")
end
if not none_err or none_err == "" then
    fail("expected status() to return an error message outside a git repository")
end

print("PASS: quarker.git status/stage/unstage")
