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
elseif cmd == "scope" then
    local sub = arg[2]
    if sub == "switch" then
        -- Accept the name in any position; --create may precede or follow it.
        local name, create
        for i = 3, #arg do
            if arg[i] == "--create" then
                create = true
            elseif not name then
                name = arg[i]
            end
        end
        if not name or name == "" then
            io.stderr:write("scope switch: missing scope name\n")
            os.exit(1)
        end
        local q = require("quarker")
        if create then
            -- Idempotent: create_scope returns false (and notifies stderr) if it
            -- already exists; we only care that switch succeeds afterward.
            q.create_scope(name)
        end
        if not q.switch_scope(name) then
            os.exit(1)
        end
        os.exit(0)
    else
        io.stderr:write("usage: scope switch <name> [--create]\n")
        os.exit(1)
    end
else
    io.stderr:write("usage: nvim -l cli.lua <mark <path...> | mark-plan <planfile> | scope switch <name> [--create]>\n")
    os.exit(1)
end
