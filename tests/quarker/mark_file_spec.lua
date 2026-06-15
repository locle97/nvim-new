-- Run from repo root:
--   XDG_DATA_HOME="$(mktemp -d)" nvim -l tests/quarker/mark_file_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg) io.stderr:write("FAIL: " .. msg .. "\n"); os.exit(1) end

-- Isolate scope: chdir to a fresh non-git temp dir so base_scope == cwd.
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.chdir(tmp)

local q = require("quarker")
if type(q.mark_file) ~= "function" then fail("mark_file is not a function") end

local target = tmp .. "/src/a.lua"
local added = q.mark_file(target)
if added ~= true then fail("expected mark_file to return true on first mark") end

local marks = q.get_marks()
if #marks ~= 1 then fail("expected 1 mark, got " .. #marks) end
if marks[1].path ~= "src/a.lua" then
  fail("expected relative path 'src/a.lua', got '" .. tostring(marks[1].path) .. "'")
end

-- Dedupe: marking the same path again must not add a duplicate.
local again = q.mark_file(target)
if again ~= false then fail("expected mark_file to return false on duplicate") end
marks = q.get_marks()
if #marks ~= 1 then fail("expected still 1 mark after duplicate, got " .. #marks) end

io.stderr:write("PASS mark_file_spec\n")
os.exit(0)
