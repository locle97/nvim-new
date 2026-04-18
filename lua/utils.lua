M = {}

M.remove_other_buffers = function()
    local current_buf = vim.api.nvim_get_current_buf()
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        if buf ~= current_buf and vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

-- Get the scope (git root or CWD)
local function get_scope()
    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    if vim.v.shell_error == 0 and git_root and git_root ~= "" then
        return git_root
    else
        return vim.fn.getcwd()
    end
end

-- Get relative path from scope
local function get_relative_path(filepath, scope)
    if filepath:sub(1, #scope) == scope then
        local relative = filepath:sub(#scope + 1)
        if relative:sub(1, 1) == "/" then
            relative = relative:sub(2)
        end
        return relative
    end
    return filepath
end

-- Copy relative path to clipboard
M.copy_relative_path = function()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to copy path", vim.log.levels.WARN)
        return
    end
    local scope = get_scope()
    local relative_path = get_relative_path(filepath, scope)
    vim.fn.setreg("+", relative_path)
    vim.notify("Copied: " .. relative_path, vim.log.levels.INFO)
end

-- Copy relative path with line range to clipboard (for visual selection)
M.copy_relative_path_with_lines = function()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to copy path", vim.log.levels.WARN)
        return
    end
    local scope = get_scope()
    local relative_path = get_relative_path(filepath, scope)
    local l1 = vim.fn.line("v")
    local l2 = vim.fn.line(".")
    local start_line = math.min(l1, l2)
    local end_line = math.max(l1, l2)
    local result = relative_path .. ":" .. start_line .. "-" .. end_line
    vim.fn.setreg("+", result)
    vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

-- Git panel: nvim-tree showing only git-dirty files as a side panel
do
    local git_panel_open = false
    local events_subscribed = false

    M.toggle_git_explorer = function()
        local api = require("nvim-tree.api")
        local view = require("nvim-tree.view")

        if not events_subscribed then
            events_subscribed = true
            api.events.subscribe(api.events.Event.TreeClose, function()
                if git_panel_open then
                    git_panel_open = false
                    require("nvim-tree").setup(vim.deepcopy(require("configs.nvimtree")))
                end
            end)
        end

        if git_panel_open then
            api.tree.close()
            return
        end

        if view.is_visible() then
            api.tree.close()
        end

        local opts = vim.tbl_deep_extend("force", vim.deepcopy(require("configs.nvimtree")), {
            view = {
                side = "left",
                width = 40,
                float = { enable = false },
            },
            filters = {
                git_clean = true,
            },
        })

        require("nvim-tree").setup(opts)
        git_panel_open = true
        api.tree.open()
    end
end

-- Git commit with dressing input
M.git_commit = function()
    vim.ui.input({ prompt = "Commit message: " }, function(msg)
        if not msg or msg == "" then
            return
        end
        local output = vim.fn.systemlist({ "git", "commit", "-m", msg, "--no-verify" })
        if vim.v.shell_error == 0 then
            vim.notify("Committed: " .. msg, vim.log.levels.INFO)
        else
            vim.notify(table.concat(output, "\n"), vim.log.levels.ERROR)
        end
    end)
end

return M
