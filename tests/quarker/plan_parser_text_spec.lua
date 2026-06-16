-- Run from repo root: nvim -l tests/quarker/plan_parser_text_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg) io.stderr:write("FAIL: " .. msg .. "\n"); os.exit(1) end

local parser = require("quarker.plan_parser")

if type(parser.extract_paths_from_text) ~= "function" then
  fail("extract_paths_from_text is not a function")
end

-- A raw visual selection: path bullets plus inline code that must NOT match.
local sample = [[
- Create: `lua/quarker/selection.lua`
- Modify: `lua/quarker/init.lua:312-342`
- Test: `tests/quarker/selection_spec.lua`

Run `git add lua/quarker/init.lua` then `:Quarker mark`.
Also see `vim.fn.expand` and `README`.
]]

local paths = parser.extract_paths_from_text(sample)

local expected = {
  "lua/quarker/selection.lua",       -- has a slash, kept
  "lua/quarker/init.lua",            -- range stripped; dup from git-add token is ignored (has spaces)
  "tests/quarker/selection_spec.lua",
  -- `git add lua/...` rejected (whitespace), `:Quarker mark` rejected (whitespace),
  -- `vim.fn.expand` rejected (no slash), `README` rejected (no slash)
}

if #paths ~= #expected then
  fail("expected " .. #expected .. " paths, got " .. #paths .. " (" .. table.concat(paths, ", ") .. ")")
end
for i, e in ipairs(expected) do
  if paths[i] ~= e then
    fail("path " .. i .. ": expected '" .. e .. "', got '" .. tostring(paths[i]) .. "'")
  end
end

io.stderr:write("PASS plan_parser_text_spec\n")
os.exit(0)
