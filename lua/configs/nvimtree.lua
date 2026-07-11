local HEIGHT_RATIO = 1
local WIDTH_RATIO = 1

-- Anything staged in the index for this path? (index status is the first column
-- of --porcelain; " " means unstaged, "?" means untracked)
local function has_staged(dir, path)
    local lines = vim.fn.systemlist({ "git", "-C", dir, "status", "--porcelain", "--", path })
    if vim.v.shell_error ~= 0 then
        return nil, table.concat(lines, "\n")
    end
    for _, line in ipairs(lines) do
        local index = line:sub(1, 1)
        if index ~= " " and index ~= "?" and index ~= "" then
            return true
        end
    end
    return false
end

local function toggle_stage()
    local api = require("nvim-tree.api")
    local node = api.tree.get_node_under_cursor()
    if not node or not node.absolute_path or node.name == ".." then
        return
    end

    local path = node.absolute_path
    local dir = node.type == "directory" and path or vim.fn.fnamemodify(path, ":h")

    local staged, err = has_staged(dir, path)
    if staged == nil then
        vim.notify(err, vim.log.levels.ERROR)
        return
    end

    local cmd = staged and { "git", "-C", dir, "restore", "--staged", "--", path }
        or { "git", "-C", dir, "add", "--", path }
    local output = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
        vim.notify(table.concat(output, "\n"), vim.log.levels.ERROR)
        return
    end

    api.tree.reload()
    vim.notify((staged and "Unstaged: " or "Staged: ") .. node.name, vim.log.levels.INFO)
end

return {
    on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.config.mappings.default_on_attach(bufnr)
        vim.keymap.set("n", "<leader>gs", toggle_stage, {
            buffer = bufnr,
            noremap = true,
            silent = true,
            nowait = true,
            desc = "nvim-tree: stage/unstage file under cursor",
        })
    end,
    filters = { dotfiles = false },
    disable_netrw = true,
    hijack_cursor = true,
    sync_root_with_cwd = true,
    update_focused_file = {
        enable = true,
        update_root = false,
    },
    notify = {
        threshold = vim.log.levels.ERROR,
        absolute_path = true,
    },
    view = {
        centralize_selection = true,
        cursorline = true,
        debounce_delay = 15,
        side = "left",
        preserve_window_proportions = false,
        number = true,
        relativenumber = true,
        signcolumn = "yes",
        width = 30,
        float = {
            enable = true,
            open_win_config = function()
                local screen_w = vim.opt.columns:get()
                local screen_h = vim.opt.lines:get() - vim.opt.cmdheight:get()
                local window_w = screen_w * WIDTH_RATIO
                local window_h = screen_h * HEIGHT_RATIO
                local window_w_int = math.floor(window_w)
                local window_h_int = math.floor(window_h)
                local center_x = (screen_w - window_w) / 2
                local center_y = ((vim.opt.lines:get() - window_h) / 2) - vim.opt.cmdheight:get()
                return {
                    border = "none",
                    relative = "editor",
                    row = center_y,
                    col = center_x,
                    width = window_w_int,
                    height = window_h_int,
                }
            end,
        },
    },
    renderer = {
        root_folder_label = false,
        highlight_git = true,
        indent_markers = { enable = true },
        icons = {
            glyphs = {
                default = "󰈚",
                folder = {
                    default = "",
                    empty = "",
                    empty_open = "",
                    open = "",
                    symlink = "",
                },
                git = { unmerged = "" },
            },
        },
    },
}
