return {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000, -- load before everything else
    config = function()
        require("catppuccin").setup({
            flavour = "mocha",
            transparent_background = true,
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
        vim.cmd.colorscheme("catppuccin")
    end,
}
