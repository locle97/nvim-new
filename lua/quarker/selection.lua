-- Interactive "mark files from a visual selection" flow.
-- Parsing is delegated to quarker.plan_parser; this module owns the editor
-- side: reading the visual range, computing per-path status, confirming the
-- marks, and rendering the confirm float.
local M = {}

local function get_quarker()
    return require("quarker")
end

-- Build a set of currently-marked relative paths for O(1) lookup.
local function marked_set()
    local set = {}
    for _, mark in ipairs(get_quarker().get_marks()) do
        set[mark.path] = true
    end
    return set
end

-- For each relative path, report whether it is already marked in the active
-- scope and whether it currently exists on disk. Existence is informational
-- only — missing paths are still markable (plans reference files to create).
-- Returns: { { path = string, marked = bool, exists = bool }, ... }
function M.compute_statuses(paths)
    local base = get_quarker().get_scope()
    local marked = marked_set()
    local rows = {}

    for _, path in ipairs(paths) do
        local abs = base .. "/" .. path
        table.insert(rows, {
            path = path,
            marked = marked[path] == true,
            exists = vim.fn.filereadable(abs) == 1,
        })
    end

    return rows
end

-- Mark every relative path into the active scope, regardless of on-disk
-- existence. Reuses quarker.mark_file (returns true when newly added, false
-- when already marked) so the on-disk format cannot drift.
-- Returns: { added = number, duplicate = number }
function M.confirm_marks(paths)
    local base = get_quarker().get_scope()
    local added, duplicate = 0, 0

    for _, path in ipairs(paths) do
        local abs = base .. "/" .. path
        if get_quarker().mark_file(abs) then
            added = added + 1
        else
            duplicate = duplicate + 1
        end
    end

    return { added = added, duplicate = duplicate }
end

return M
