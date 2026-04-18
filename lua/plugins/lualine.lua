return {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        -- Skip in headless mode (no UI → catppuccin theme colors unavailable)
        if #vim.api.nvim_list_uis() == 0 then return end

        -- Quarker scope component
        local function quarker_scope()
            local ok, q = pcall(require, "quarker")
            if not ok then return "" end
            local s = q.statusline()
            if not s or s == "" then return "" end
            return s
        end

        require("lualine").setup({
            options = {
                theme = "catppuccin",
                globalstatus = true,
                component_separators = { left = "", right = "" },
                section_separators = { left = "", right = "" },
            },
            sections = {
                lualine_a = { "mode" },
                lualine_b = { "branch", "diff" },
                lualine_c = { { "filename", path = 1 }, quarker_scope },
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
                lualine_c = { { "filename", path = 1 } },
                lualine_x = { "location" },
            },
        })
    end,
}
