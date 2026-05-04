return {
    "akinsho/bufferline.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        require("bufferline").setup({
            options = {
                mode = "buffers",
                separator_style = "thin",
                show_buffer_close_icons = true,
                show_close_icon = false,
                color_icons = true,
                diagnostics = "nvim_lsp",
                offsets = {
                    {
                        filetype = "NvimTree",
                        text = "File Explorer",
                        highlight = "Directory",
                        separator = true,
                    },
                },
            },
        })

        -- Strip the bg from every BufferLine* highlight group so the tabline
        -- inherits the (transparent) terminal background instead of the
        -- plugin's hardcoded greys.
        local function transparent_bufferline()
            for _, g in ipairs(vim.fn.getcompletion("BufferLine", "highlight")) do
                local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
                hl.bg = "NONE"
                hl.ctermbg = "NONE"
                vim.api.nvim_set_hl(0, g, hl)
            end
        end

        vim.api.nvim_create_autocmd("VimEnter", { callback = transparent_bufferline })
        vim.api.nvim_create_autocmd("ColorScheme", { callback = transparent_bufferline })
        vim.api.nvim_create_autocmd("User", {
            pattern = "NvThemeReload",
            callback = transparent_bufferline,
        })
    end,
}
