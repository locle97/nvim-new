return {
    -- NvChad's theming engine: compiles 60+ themes to cache files at build time.
    -- Depends on `nvchad/ui` because base46's init.lua does `require("nvconfig")`
    -- at module-load, and nvconfig.lua ships inside the ui plugin's rtp.
    {
        "nvchad/base46",
        lazy = false,
        priority = 1000,
        dependencies = { "nvchad/ui" },
        build = function()
            require("base46").load_all_highlights()
        end,
    },

    -- Provides `nvconfig` (config schema) and `nvchad.themes` (the picker).
    -- We deliberately do NOT call `require "nvchad"` — that wires up the
    -- bundled statusline/tabufline, which would clash with lualine + bufferline.
    { "nvchad/ui",                   lazy = true },
    { "nvchad/volt",                 lazy = true },
    { "nvim-lua/plenary.nvim" },
    { "nvim-tree/nvim-web-devicons", lazy = true },
}
