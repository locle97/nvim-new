return {
    {
        "kdheepak/lazygit.nvim",
        lazy = false,
        config = function()
            vim.g.lazygit_floating_window_scaling_factor = 1
        end,
    },
    {
        "lewis6991/gitsigns.nvim",
        event = "User FilePost",
        opts = {
            signs = {
                delete = { text = "󰍵" },
                changedelete = { text = "󱕖" },
            },
        },
    },
}
