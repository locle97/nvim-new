return {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {
        diff = {
            layout = "inline",
        },
        explorer = {
            -- Full-screen explorer, like the nvim-tree float. `layout.arrange`
            -- re-pins the panel to this width on every show/hide and clamps it
            -- to the available columns, so this survives terminal resizes.
            width = 9999,
            focus_on_select = true,
        },
        keymaps = {
            view = {
                -- Replaced below by a toggle that also focuses the explorer.
                toggle_explorer = false,
                focus_explorer = "<leader>b",
            },
        },
    },
    config = function(_, opts)
        require("codediff").setup(opts)

        local function get_explorer()
            local lifecycle = require("codediff.ui.lifecycle")
            return lifecycle.get_explorer(vim.api.nvim_get_current_tabpage())
        end

        local function is_visible(explorer)
            local winid = explorer.split and explorer.split.winid
            return not explorer.is_hidden and winid and vim.api.nvim_win_is_valid(winid)
        end

        -- NvimTreeToggle semantics: hide when focused, otherwise show *and* focus.
        -- The built-in toggle only shows, which strands the cursor in the diff
        -- window hidden behind the full-screen explorer.
        local function toggle_explorer()
            local explorer = get_explorer()
            if not explorer then
                return
            end

            local actions = require("codediff.ui.explorer")
            if is_visible(explorer) then
                if vim.api.nvim_get_current_win() == explorer.split.winid then
                    actions.toggle_visibility(explorer)
                else
                    vim.api.nvim_set_current_win(explorer.split.winid)
                end
                return
            end

            actions.toggle_visibility(explorer)
            vim.schedule(function()
                local winid = explorer.split and explorer.split.winid
                if winid and vim.api.nvim_win_is_valid(winid) then
                    vim.api.nvim_set_current_win(winid)
                end
            end)
        end

        local function hide_explorer()
            local explorer = get_explorer()
            if explorer and is_visible(explorer) then
                require("codediff.ui.explorer").toggle_visibility(explorer)
            end
        end

        local group = vim.api.nvim_create_augroup("codediff_fullscreen_explorer", { clear = true })

        -- Diff buffers holding the back-to-explorer keymaps, tracked so they can be unmapped
        -- on close and stop shadowing <Esc>/<leader>e in what are ordinary file buffers.
        local mapped = {}
        local back_keys = { "<leader>e" }

        -- Bind on buffer entry, not on the CodeDiffOpen event: that event only fires when the
        -- view is first created, while picking another file just swaps the buffer. The session
        -- record can't identify that buffer either -- it only catches up once the diff has been
        -- computed asynchronously -- but being inside a diff tab at all is enough to know the
        -- buffer is a diff pane.
        vim.api.nvim_create_autocmd("BufEnter", {
            group = group,
            callback = function(args)
                if mapped[args.buf] or vim.bo[args.buf].filetype == "codediff-explorer" then
                    return
                end
                if not require("codediff.ui.lifecycle").get_session(vim.api.nvim_get_current_tabpage()) then
                    return
                end
                for _, lhs in ipairs(back_keys) do
                    vim.keymap.set("n", lhs, toggle_explorer, {
                        buffer = args.buf,
                        silent = true,
                        nowait = true,
                        desc = "Toggle diff explorer",
                    })
                end
                mapped[args.buf] = true
            end,
        })

        -- Diff tabs still open re-map their buffers on the next BufEnter.
        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffClose",
            callback = function()
                for bufnr in pairs(mapped) do
                    if vim.api.nvim_buf_is_valid(bufnr) then
                        for _, lhs in ipairs(back_keys) do
                            pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
                        end
                    end
                end
                mapped = {}
            end,
        })

        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("codediff_explorer_keys", { clear = true }),
            pattern = "codediff-explorer",
            callback = function(args)
                -- Also use `o` (in addition to <CR>) to select/expand in the explorer.
                vim.keymap.set("n", "o", "<CR>", { buffer = args.buf, remap = true, silent = true })
                vim.keymap.set("n", "<leader>e", toggle_explorer, { buffer = args.buf, silent = true })

                -- Opening a file hides the explorer, so the diff gets the whole tab.
                -- This wraps the keypress rather than the CodeDiffFileSelect event:
                -- the event also fires for the initial auto-selected file and on every
                -- auto-refresh, which would yank the explorer closed while browsing.
                -- The explorer's keymaps are only installed once `create` finishes, so
                -- defer until the original <CR> exists and wrap it.
                vim.schedule(function()
                    if not vim.api.nvim_buf_is_valid(args.buf) then
                        return
                    end

                    local select
                    vim.api.nvim_buf_call(args.buf, function()
                        select = vim.fn.maparg("<CR>", "n", false, true)
                    end)
                    if not (select and select.callback) then
                        return
                    end

                    vim.keymap.set("n", "<CR>", function()
                        local explorer = get_explorer()
                        local node = explorer and explorer.tree and explorer.tree:get_node()
                        local data = node and node.data
                        -- Groups and directories toggle a fold; only files open a diff.
                        local opens_file = data ~= nil and data.type ~= "group" and data.type ~= "directory"

                        select.callback()

                        if opens_file then
                            -- Runs after the plugin's own focus_on_select handler, which
                            -- was scheduled first and moves the cursor into the diff.
                            vim.schedule(hide_explorer)
                        end
                    end, { buffer = args.buf, silent = true, nowait = true })
                end)
            end,
        })
    end,
}
