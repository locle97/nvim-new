-- Run from repo root:
--   XDG_DATA_HOME="$(mktemp -d)" nvim -l tests/quarker/hidden_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg)
    io.stderr:write("FAIL: " .. msg .. "\n")
    os.exit(1)
end

local function expect(condition, msg)
    if not condition then
        fail(msg)
    end
end

-- Every call is scoped explicitly, so the tests never touch the real repo's data.
local scope = vim.fn.tempname()
vim.fn.mkdir(scope, "p")

local hidden = require("quarker.hidden")

-- Nothing hidden yet: a repo with no hidden.json reads as the empty set.
expect(not hidden.is_hidden("docs/plan.md", scope), "a fresh repo should hide nothing")
expect(#hidden.list(scope) == 0, "a fresh repo's list should be empty")

-- Hiding survives a reload from disk.
hidden.hide("docs/plan.md", scope)
hidden.hide("docs/notes.md", scope)
hidden.invalidate(scope)

expect(hidden.is_hidden("docs/plan.md", scope), "docs/plan.md should still be hidden after a reload")
expect(hidden.is_hidden("docs/notes.md", scope), "docs/notes.md should still be hidden after a reload")
expect(not hidden.is_hidden("lua/init.lua", scope), "an unhidden path should not be hidden")

-- list() is sorted, so the file on disk is stable.
local paths = hidden.list(scope)
expect(
    #paths == 2 and paths[1] == "docs/notes.md" and paths[2] == "docs/plan.md",
    "expected a sorted list of both paths, got: " .. vim.inspect(paths)
)

-- Unhiding survives a reload too.
hidden.unhide("docs/plan.md", scope)
hidden.invalidate(scope)

expect(not hidden.is_hidden("docs/plan.md", scope), "docs/plan.md should be unhidden after a reload")
expect(hidden.is_hidden("docs/notes.md", scope), "unhiding one path should not unhide the other")

-- A corrupt hidden.json must not take the git tab down: it reads as nothing hidden.
local hidden_file = require("quarker").get_repo_dir(scope) .. "/hidden.json"
local fd = io.open(hidden_file, "w")
fd:write("{ not json")
fd:close()
hidden.invalidate(scope)

expect(not hidden.is_hidden("docs/notes.md", scope), "a corrupt hidden.json should read as nothing hidden")
expect(#hidden.list(scope) == 0, "a corrupt hidden.json should read as an empty list")

-- ...and the next write repairs it.
hidden.hide("docs/notes.md", scope)
hidden.invalidate(scope)
expect(hidden.is_hidden("docs/notes.md", scope), "hiding should repair a corrupt hidden.json")

-- Hidden state is per repository.
local other_scope = vim.fn.tempname()
vim.fn.mkdir(other_scope, "p")
expect(not hidden.is_hidden("docs/notes.md", other_scope), "hidden state should not leak across repositories")

print("ok - hidden_spec")
