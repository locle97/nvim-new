return {
    'prichrd/netrw.nvim',
    opts = {},
    lazy = false,
    config = function()
        local g = vim.g

        require("netrw").setup({
            -- File icons to use when `use_devicons` is false or if
            -- no icon is found for the given file type.
            icons = {
                symlink = '',
                directory = '',
                file = '',
            },
            -- Uses mini.icon or nvim-web-devicons if true, otherwise use the file icon specified above
            use_devicons = true,
        })

        -- Modify keymap for netrw
        vim.api.nvim_create_autocmd('filetype', {
            pattern = 'netrw',
            desc = 'Better mappings for netrw',
            callback = function()
                local bind = function(lhs, rhs)
                    vim.keymap.set('n', lhs, rhs, { remap = true, buffer = true })
                end

                -- edit new file
                bind('o', '<CR>')
                vim.keymap.set('n', 'q', '<C-^>', { noremap = true, buffer = true, silent = true, nowait = true })
            end
        })

        -- Netrw
        g.netrw_liststyle = 3
        g.netrw_banner = 0
        g.netrw_hide = 1
        g.netrw_browse_split = 0
    end
}
