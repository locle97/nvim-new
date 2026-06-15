-- Run from repo root: nvim -l tests/quarker/plan_parser_spec.lua
local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path

local function fail(msg) io.stderr:write("FAIL: " .. msg .. "\n"); os.exit(1) end

local parser = require("quarker.plan_parser")

local sample = [[
# Example Plan

### Task 1: First

**Files:**
- Create: `lua/quarker/cli.lua`
- Modify: `lua/quarker/init.lua:312-342`
- Test: `tests/quarker/cli_spec.sh`

- [ ] Step 1: do a thing

```bash
git add lua/quarker/init.lua
```

### Task 2: Second

**Files:**
- Modify: `lua/quarker/init.lua:400-410`
- Create: `hooks/mark-plan-files.sh`
]]

local paths = parser.extract_paths(sample)

local expected = {
  "lua/quarker/cli.lua",       -- task 1 create
  "lua/quarker/init.lua",      -- task 1 modify, range stripped
  "tests/quarker/cli_spec.sh", -- task 1 test
  "hooks/mark-plan-files.sh",  -- task 2 create (init.lua dedup'd away)
}

if #paths ~= #expected then
  fail("expected " .. #expected .. " paths, got " .. #paths .. " (" .. table.concat(paths, ", ") .. ")")
end
for i, e in ipairs(expected) do
  if paths[i] ~= e then
    fail("path " .. i .. ": expected '" .. e .. "', got '" .. tostring(paths[i]) .. "'")
  end
end

io.stderr:write("PASS plan_parser_spec\n")
os.exit(0)
