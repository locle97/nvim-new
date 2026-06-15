-- Headless entrypoint for `nvim -l`. Reuses the real Quarker plugin so the
-- on-disk mark format cannot drift. stdout is kept clean for callers.

-- Resolve the config's lua/ dir from this script's own path so require() works
-- regardless of cwd. This file lives at <luadir>/quarker/cli.lua.
local self = arg[0]
local luadir = self:gsub("[/\\]quarker[/\\]cli%.lua$", "")
package.path = luadir .. "/?.lua;" .. luadir .. "/?/init.lua;" .. package.path

-- Route plugin notifications/prints to stderr so stdout stays parseable.
vim.notify = function(msg)
    if msg ~= nil then io.stderr:write(tostring(msg) .. "\n") end
end
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    io.stderr:write(table.concat(parts, "\t") .. "\n")
end

local cmd = arg[1]

if cmd == "mark" then
    local q = require("quarker")
    for i = 2, #arg do
        local abs = vim.fn.fnamemodify(arg[i], ":p")
        q.mark_file(abs)
    end
    os.exit(0)
elseif cmd == "mark-plan" then
    local planfile = arg[2]
    if not planfile or planfile == "" then
        io.stderr:write("mark-plan: missing plan file argument\n")
        os.exit(1)
    end
    local f = io.open(planfile, "r")
    if not f then
        io.stderr:write("mark-plan: cannot read " .. planfile .. "\n")
        os.exit(1)
    end
    local content = f:read("*a")
    f:close()

    local paths = require("quarker.plan_parser").extract_paths(content or "")
    local q = require("quarker")
    for _, p in ipairs(paths) do
        q.mark_file(vim.fn.fnamemodify(p, ":p"))
    end
    os.exit(0)
else
    io.stderr:write("usage: nvim -l cli.lua <mark <path...> | mark-plan <planfile>>\n")
    os.exit(1)
end
