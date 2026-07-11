return {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {
        diff = {
            layout = "inline",
        },
        keymaps = {
            view = {
                toggle_explorer = "<leader>e",
                focus_explorer = "<leader>b",
                toggle_stage = "<leader>gs",
            },
        },
    },
    config = function(_, opts)
        require("codediff").setup(opts)

        -- Also use `o` (in addition to <CR>) to select/expand in the explorer.
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("codediff_explorer_keys", { clear = true }),
            pattern = "codediff-explorer",
            callback = function(args)
                vim.keymap.set("n", "o", "<CR>", { buffer = args.buf, remap = true, silent = true })
            end,
        })
    end,
}
