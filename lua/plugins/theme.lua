return {
    -- NvChad's theming engine: compiles 60+ themes to cache files at build time.
    {
        "nvchad/base46",
        lazy = false,
        priority = 1000,
        build = function()
            require("base46").load_all_highlights()
        end,
    },

    -- NvChad UI provides the `nvchad.themes` picker module.
    -- Loaded lazily on the theme-switcher keybinding so its statusline/tabufline
    -- code never runs (we use lualine + bufferline instead).
    {
        "nvchad/ui",
        keys = {
            {
                "<leader>th",
                function() require("nvchad.themes").open() end,
                desc = "Theme switcher",
            },
        },
        dependencies = { "nvchad/volt", "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    },

    { "nvchad/volt",         lazy = true },
    { "nvim-lua/plenary.nvim" },
    { "nvim-tree/nvim-web-devicons", lazy = true },
}
