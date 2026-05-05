return {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = "ToggleTerm",
    -- also loaded on the keymap triggers in mappings.lua
    keys = { "<A-v>", "<A-h>", "<A-i>", "<A-c>" },
    config = function()
        require("toggleterm").setup({
            size = function(term)
                if term.direction == "horizontal" then
                    return 15
                elseif term.direction == "vertical" then
                    return math.floor(vim.o.columns * 0.4)
                end
                return 20
            end,
            shade_terminals = false,
            persist_size = true,
            persist_mode = true,
            direction = "float",
            float_opts = {
                border = "curved",
            },
        })

        local Terminal = require("toggleterm.terminal").Terminal
        local claude = Terminal:new({
            cmd = "claude",
            hidden = true,
            direction = "float",
            float_opts = { border = "curved" },
        })

        vim.keymap.set({ "n", "t" }, "<A-c>", function() claude:toggle() end,
            { desc = "Toggle Claude terminal" })
    end,
}
