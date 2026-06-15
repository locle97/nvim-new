-- Pure parser for writing-plans "Files:" blocks.
-- Extracts the backtick-quoted Create/Modify/Test paths, strips any trailing
-- :line or :start-end range, dedupes, and preserves first-seen order.
local M = {}

local function strip_range(path)
    path = path:gsub(":%d+%-%d+$", "")
    path = path:gsub(":%d+$", "")
    return path
end

-- content: the full markdown text of a plan document
-- returns: array of relative path strings
function M.extract_paths(content)
    local paths = {}
    local seen = {}
    local in_block = false

    for line in (content .. "\n"):gmatch("(.-)\n") do
        if line:find("**Files:**", 1, true) then
            in_block = true
        elseif in_block then
            if line:match("^%s*$") or line:match("^%s*#") then
                in_block = false
            else
                local labeled = line:find("Create:") or line:find("Modify:") or line:find("Test:")
                if labeled then
                    local path = line:match("`([^`]+)`")
                    if path then
                        path = strip_range(path)
                        if path ~= "" and not seen[path] then
                            seen[path] = true
                            table.insert(paths, path)
                        end
                    end
                end
            end
        end
    end

    return paths
end

return M
