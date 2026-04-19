return {
    {
        "catppuccin/nvim",
        name = "catppuccin",
        lazy = false,
        priority = 1000, -- load before everything else
        config = function()
            require("catppuccin").setup({
                flavour = "mocha",
                transparent_background = false,
                integrations = {
                    nvimtree = true,
                    telescope = { enabled = true },
                    gitsigns = true,
                    indent_blankline = { enabled = true },
                    cmp = true,
                    treesitter = true,
                    bufferline = true,
                    mini = { enabled = true },
                },
            })
            vim.cmd.colorscheme('catppuccin')
        end,
    },
    {
        "vague-theme/vague.nvim",
        lazy = false,
        priority = 1000, -- load before everything else
        config = function()
            require('vague').setup({
              transparent = true, -- If true, background is not set
              bold = true, -- Disable bold globally
              italic = false, -- Disable italic globally
            })
            -- vim.cmd.colorscheme('vague')
        end,
    }
}
