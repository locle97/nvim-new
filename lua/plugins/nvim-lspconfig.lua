return {
    {
        "stevearc/conform.nvim",
        opts = require("configs.conform"),
    },
    {
        "neovim/nvim-lspconfig",
        event = "User FilePost",
        config = function()
            require("configs.lspconfig").defaults()
        end,
    },
}
