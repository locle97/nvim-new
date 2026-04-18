return {
    "echasnovski/mini.nvim",
    event = "BufEnter",
    config = function()
        require("mini.cursorword").setup {}
    end,
}
