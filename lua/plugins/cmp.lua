return {
    "saghen/blink.cmp",
    event = "InsertEnter",
    version = "*",
    dependencies = {
        {
            "L3MON4D3/LuaSnip",
            dependencies = "rafamadriz/friendly-snippets",
            opts = { history = true, updateevents = "TextChanged,TextChangedI" },
            config = function(_, opts)
                require("luasnip").config.set_config(opts)
                require("luasnip.loaders.from_vscode").lazy_load()
                require("luasnip.loaders.from_snipmate").load()
                require("luasnip.loaders.from_lua").load()
                require("luasnip.loaders.from_lua").load({ paths = "~/.config/nvim/lua/snippets/" })
                vim.api.nvim_create_autocmd("InsertLeave", {
                    callback = function()
                        local ls = require("luasnip")
                        if ls.session.current_nodes[vim.api.nvim_get_current_buf()]
                            and not ls.session.jump_active
                        then
                            ls.unlink_current()
                        end
                    end,
                })
            end,
        },
        {
            "windwp/nvim-autopairs",
            opts = {
                fast_wrap = {},
                disable_filetype = { "TelescopePrompt", "vim" },
            },
        },
        "giuxtaposition/blink-cmp-copilot",
    },
    opts = {
        keymap = {
            preset = "none",
            ["<C-p>"] = { "select_prev", "fallback" },
            ["<C-n>"] = { "select_next", "fallback" },
            ["<C-d>"] = { "scroll_documentation_up", "fallback" },
            ["<C-f>"] = { "scroll_documentation_down", "fallback" },
            ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
            ["<C-e>"] = { "hide", "fallback" },
            ["<CR>"] = { "accept", "fallback" },
            ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
            ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        },

        appearance = {
            kind_icons = {
                Text = "󰉿",
                Method = "󰆧",
                Function = "󰊕",
                Constructor = "",
                Field = "󰜢",
                Variable = "󰀫",
                Class = "󰠱",
                Interface = "",
                Module = "",
                Property = "󰜢",
                Unit = "󰑭",
                Value = "󰎠",
                Enum = "",
                Keyword = "󰌋",
                Snippet = "",
                Color = "󰏘",
                File = "󰈙",
                Reference = "󰈇",
                Folder = "󰉋",
                EnumMember = "",
                Constant = "󰏿",
                Struct = "󰙅",
                Event = "",
                Operator = "󰆕",
                TypeParameter = "",
            },
        },

        completion = {
            accept = {
                auto_brackets = { enabled = true },
            },
            menu = {
                border = "rounded",
                scrollbar = false,
                draw = {
                    columns = {
                        { "label", "label_description", gap = 1 },
                        { "kind_icon", "kind", gap = 1 },
                        { "source_name" },
                    },
                },
            },
            documentation = {
                auto_show = true,
                window = { border = "rounded" },
            },
        },

        snippets = { preset = "luasnip" },

        sources = {
            default = { "lsp", "path", "snippets", "buffer", "copilot" },
            providers = {
                copilot = {
                    name = "Copilot",
                    module = "blink-cmp-copilot",
                    score_offset = 100,
                    async = true,
                },
            },
        },
    },
}
