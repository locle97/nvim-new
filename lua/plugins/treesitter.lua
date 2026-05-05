return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
        local parsers = {
            "lua", "css", "dockerfile", "go", "html",
            "javascript", "json", "markdown", "markdown_inline",
            "python", "tsx", "vue", "c_sharp"
        }

        require("nvim-treesitter").install(parsers)

        local installed = {}
        for _, lang in ipairs(require("nvim-treesitter.config").get_installed("parsers")) do
            installed[lang] = true
        end

        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("treesitter_attach", { clear = true }),
            callback = function(args)
                local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
                if not lang or not installed[lang] then return end

                pcall(vim.treesitter.start, args.buf, lang)
                vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })
    end,
}
