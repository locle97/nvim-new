return {
    "nvim-telescope/telescope.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
        "nvim-telescope/telescope-live-grep-args.nvim",
    },
    cmd = "Telescope",
    config = function()
        local telescope = require("telescope")
        local actions = require("telescope.actions")

        telescope.setup({
            defaults = {
                prompt_prefix = "   ",
                selection_caret = " ",
                entry_prefix = " ",
                sorting_strategy = "ascending",
                layout_config = {
                    horizontal = {
                        prompt_position = "top",
                        preview_width = 0.40,
                    },
                    width = { padding = 0 },
                    height = { padding = 0 },
                },
                mappings = {
                    n = { ["q"] = actions.close },
                },
                path_display = { "filename_first" },
            },
            pickers = {
                lsp_references = {
                    path_display = { "filename_first" },
                },
            },
            extensions = {
                live_grep_args = {
                    auto_quoting = false,
                },
            },
        })

        telescope.load_extension("live_grep_args")
    end,
}
