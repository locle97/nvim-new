return {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    cmd = { "TSInstall", "TSBufEnable", "TSBufDisable", "TSModuleInfo" },
    build = ":TSUpdate",
    opts = {
        ensure_installed = {
            "lua", "luadoc", "printf", "vim", "vimdoc",
            "bash", "c", "css", "dockerfile", "go", "html",
            "javascript", "json", "markdown", "markdown_inline",
            "python", "regex", "rust", "toml", "typescript",
            "tsx", "yaml",
        },
        highlight = {
            enable = true,
            use_languagetree = true,
        },
        indent = { enable = true },
    },
    config = function(_, opts)
        require("nvim-treesitter.config").setup(opts)

        -- FileType fires before lazy-load completes, so treesitter's internal
        -- handler misses the triggering buffer. Attach explicitly here and for
        -- all future buffers.
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("treesitter_attach", { clear = true }),
            callback = function(args)
                pcall(vim.treesitter.start, args.buf)
            end,
        })

        -- Also apply to the buffer that caused this lazy load.
        pcall(vim.treesitter.start, vim.api.nvim_get_current_buf())
    end,
}
