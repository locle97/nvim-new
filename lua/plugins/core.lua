return {
    -- Lua utility library (telescope, lazygit, etc. depend on this)
    "nvim-lua/plenary.nvim",

    -- File type icons
    {
        "nvim-tree/nvim-web-devicons",
        opts = {},
    },

    -- Indentation guides
    {
        "lukas-reineke/indent-blankline.nvim",
        event = "User FilePost",
        opts = {
            indent = { char = "│" },
            scope = { char = "│" },
        },
        config = function(_, opts)
            local hooks = require("ibl.hooks")
            hooks.register(hooks.type.WHITESPACE, hooks.builtin.hide_first_space_indent_level)
            require("ibl").setup(opts)
        end,
    },
}
