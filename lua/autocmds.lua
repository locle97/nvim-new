local autocmd = vim.api.nvim_create_autocmd

-- Fire "User FilePost" after the first real file buffer loads.
-- Plugins use this event to defer setup until a file is actually open.
autocmd({ "UIEnter", "BufReadPost", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("NvimFilePost", { clear = true }),
    callback = function(args)
        local file = vim.api.nvim_buf_get_name(args.buf)
        local buftype = vim.api.nvim_get_option_value("buftype", { buf = args.buf })

        if not vim.g.ui_entered and args.event == "UIEnter" then
            vim.g.ui_entered = true
        end

        if file ~= "" and buftype ~= "nofile" and vim.g.ui_entered then
            vim.api.nvim_exec_autocmds("User", { pattern = "FilePost", modeline = false })
            vim.api.nvim_del_augroup_by_name("NvimFilePost")

            vim.schedule(function()
                vim.api.nvim_exec_autocmds("FileType", {})
                if vim.g.editorconfig then
                    require("editorconfig").config(args.buf)
                end
            end)
        end
    end,
})

-- Highlight yanked text briefly
autocmd("TextYankPost", {
    desc = "Highlight when yanking text",
    group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

-- Apply TelescopeSelection highlight after colorscheme loads
autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("telescope-hl-override", { clear = true }),
    callback = function()
        vim.api.nvim_set_hl(0, "TelescopeSelection", { bg = "#34343e", fg = "#ced4df", bold = true })
    end,
})
