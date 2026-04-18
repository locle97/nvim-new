local M = {}

M.on_init = function(client, _)
    if client.supports_method("textDocument/semanticTokens") then
        client.server_capabilities.semanticTokensProvider = nil
    end
end

M.capabilities = vim.lsp.protocol.make_client_capabilities()
M.capabilities.textDocument.completion.completionItem = {
    documentationFormat = { "markdown", "plaintext" },
    snippetSupport = true,
    preselectSupport = true,
    insertReplaceSupport = true,
    labelDetailsSupport = true,
    deprecatedSupport = true,
    commitCharactersSupport = true,
    tagSupport = { valueSet = { 1 } },
    resolveSupport = {
        properties = { "documentation", "detail", "additionalTextEdits" },
    },
}

M.defaults = function()
    -- Diagnostic display config
    vim.diagnostic.config({
        virtual_text = true,
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded" },
    })

    -- Global LSP settings (capabilities + semantic token opt-out)
    if vim.lsp.config then
        vim.lsp.config("*", {
            capabilities = M.capabilities,
            on_init = M.on_init,
        })

        -- lua_ls workspace library
        vim.lsp.config("lua_ls", {
            settings = {
                Lua = {
                    workspace = {
                        library = {
                            vim.fn.expand("$VIMRUNTIME/lua"),
                            vim.fn.stdpath("data") .. "/lazy/lazy.nvim/lua/lazy",
                            "${3rd}/luv/library",
                        },
                    },
                },
            },
        })
        vim.lsp.enable("lua_ls")
    else
        require("lspconfig").lua_ls.setup({
            capabilities = M.capabilities,
            on_init = M.on_init,
            settings = {
                Lua = {
                    workspace = {
                        library = {
                            vim.fn.expand("$VIMRUNTIME/lua"),
                            vim.fn.stdpath("data") .. "/lazy/lazy.nvim/lua/lazy",
                            "${3rd}/luv/library",
                        },
                    },
                },
            },
        })
    end
end

-- Additional servers + per-server overrides
local servers = { "html", "cssls", "omnisharp", "jsonls", "ts_ls", "prettier", "vtsls", "gopls" }

vim.lsp.config("ts_ls", {
    init_options = {
        plugins = {
            {
                name = "@vue/typescript-plugin",
                location = "/usr/local/lib/node_modules/@vue/language-server/node_modules/@vue/typescript-plugin",
                languages = { "javascript", "typescript", "vue" },
            },
        },
    },
    filetypes = { "javascript", "typescript", "vue" },
})

vim.lsp.enable(servers)

return M
