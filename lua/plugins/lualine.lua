return {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        if #vim.api.nvim_list_uis() == 0 then return end

        -- Build a lualine theme from the active base46 palette so the statusline
        -- tracks the selected NvChad theme. Middle sections stay transparent.
        local function lualine_theme()
            local ok, base46 = pcall(require, "base46")
            if not ok then return "auto" end
            local c = base46.get_theme_tb("base_30")
            if not c then return "auto" end
            local none = "NONE"
            return {
                normal = {
                    a = { bg = c.blue,   fg = c.black, gui = "bold" },
                    b = { bg = none,     fg = c.white },
                    c = { bg = none,     fg = c.light_grey },
                },
                insert   = { a = { bg = c.green,  fg = c.black, gui = "bold" } },
                visual   = { a = { bg = c.purple, fg = c.black, gui = "bold" } },
                replace  = { a = { bg = c.red,    fg = c.black, gui = "bold" } },
                command  = { a = { bg = c.yellow, fg = c.black, gui = "bold" } },
                inactive = {
                    a = { bg = none, fg = c.light_grey },
                    b = { bg = none, fg = c.light_grey },
                    c = { bg = none, fg = c.light_grey },
                },
            }
        end

        local function quarker_scope()
            local ok, q = pcall(require, "quarker")
            if not ok then return "" end
            local s = q.statusline()
            if not s or s == "" then return "" end
            return s
        end

        local config = {
            options = {
                theme = lualine_theme(),
                globalstatus = true,
                component_separators = { left = "", right = "" },
                section_separators = { left = "", right = "" },
            },
            sections = {
                lualine_a = { "mode" },
                lualine_b = { "branch", "diff" },
                lualine_c = { { "filename", path = 0 }, { quarker_scope, color = { fg = "#FFD700" } } },
                lualine_x = {
                    { "diagnostics", sources = { "nvim_lsp" } },
                    {
                        function()
                            local clients = vim.lsp.get_clients({ bufnr = 0 })
                            if #clients == 0 then return "" end
                            local names = {}
                            for _, c in ipairs(clients) do
                                table.insert(names, c.name)
                            end
                            return " " .. table.concat(names, ", ")
                        end,
                    },
                    "filetype",
                },
                lualine_y = { "progress" },
                lualine_z = { "location" },
            },
            inactive_sections = {
                lualine_c = { { "filename", path = 0 } },
                lualine_x = { "location" },
            },
        }

        require("lualine").setup(config)

        vim.api.nvim_create_autocmd("User", {
            pattern = "NvThemeReload",
            callback = function()
                config.options.theme = lualine_theme()
                require("lualine").setup(config)
            end,
        })
    end,
}
