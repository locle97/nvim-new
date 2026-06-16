-- Run from repo root:
--   XDG_DATA_HOME="$(mktemp -d)" nvim -l tests/quarker/selection_status_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg) io.stderr:write("FAIL: " .. msg .. "\n"); os.exit(1) end

-- Isolate scope: chdir into a fresh non-git temp dir so base_scope == cwd.
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/src", "p")
vim.fn.chdir(tmp)

-- Create two real files on disk; leave src/c.lua missing.
for _, rel in ipairs({ "src/a.lua", "src/b.lua" }) do
  local f = io.open(tmp .. "/" .. rel, "w"); f:write("-- x\n"); f:close()
end

local q = require("quarker")
-- Pre-mark only src/a.lua.
q.mark_file(tmp .. "/src/a.lua")

local selection = require("quarker.selection")
if type(selection.compute_statuses) ~= "function" then
  fail("compute_statuses is not a function")
end

local rows = selection.compute_statuses({ "src/a.lua", "src/b.lua", "src/c.lua" })

if #rows ~= 3 then fail("expected 3 rows, got " .. #rows) end

-- src/a.lua: already marked, exists on disk
if rows[1].path ~= "src/a.lua" then fail("row1 path: " .. tostring(rows[1].path)) end
if rows[1].marked ~= true then fail("row1 should be marked") end
if rows[1].exists ~= true then fail("row1 should exist") end

-- src/b.lua: not marked, exists on disk
if rows[2].marked ~= false then fail("row2 should not be marked") end
if rows[2].exists ~= true then fail("row2 should exist") end

-- src/c.lua: not marked, missing on disk
if rows[3].marked ~= false then fail("row3 should not be marked") end
if rows[3].exists ~= false then fail("row3 should be missing") end

io.stderr:write("PASS selection_status_spec\n")
os.exit(0)
