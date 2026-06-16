-- Run from repo root:
--   XDG_DATA_HOME="$(mktemp -d)" nvim -l tests/quarker/selection_confirm_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg) io.stderr:write("FAIL: " .. msg .. "\n"); os.exit(1) end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.chdir(tmp)

local q = require("quarker")
-- Pre-mark one path so it counts as a duplicate.
q.mark_file(tmp .. "/lua/a.lua")

local selection = require("quarker.selection")
if type(selection.confirm_marks) ~= "function" then
  fail("confirm_marks is not a function")
end

-- lua/a.lua already marked (dup); lua/b.lua and lua/c.lua are new.
local result = selection.confirm_marks({ "lua/a.lua", "lua/b.lua", "lua/c.lua" })

if result.added ~= 2 then fail("expected added=2, got " .. tostring(result.added)) end
if result.duplicate ~= 1 then fail("expected duplicate=1, got " .. tostring(result.duplicate)) end

local marks = q.get_marks()
if #marks ~= 3 then fail("expected 3 marks total, got " .. #marks) end

-- Paths are stored relative to the base scope.
local got = {}
for _, m in ipairs(marks) do got[m.path] = true end
for _, want in ipairs({ "lua/a.lua", "lua/b.lua", "lua/c.lua" }) do
  if not got[want] then fail("missing mark: " .. want) end
end

io.stderr:write("PASS selection_confirm_spec\n")
os.exit(0)
