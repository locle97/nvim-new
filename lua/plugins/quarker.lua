return {
    dir = vim.fn.stdpath("config") .. "/lua/quarker",
    name = "quarker",
    dependencies = {
        "nvim-telescope/telescope.nvim",
    },
    keys = {
        {
            "<leader>m",
            function()
                require("quarker").toggle()
            end,
            desc = "Quarker: Toggle mark file"
        },
        {
            "<leader><leader>",
            function()
                require("quarker").show_marks_ui()
            end,
            desc = "Quarker: Toggle marks menu"
        },
        {
            "<leader>qs",
            function()
                require("quarker").show_scopes_ui()
            end,
            desc = "Quarker: Scope manager"
        },
        {
            "<leader>qc",
            function()
                require("quarker").show_context_ui()
            end,
            desc = "Quarker: Context manager"
        },
        -- Quick navigation keys
        {
            "<leader>1",
            function()
                require("quarker").navigate(1)
            end,
            desc = "Quarker: Navigate to mark 1"
        },
        {
            "<leader>2",
            function()
                require("quarker").navigate(2)
            end,
            desc = "Quarker: Navigate to mark 2"
        },
        {
            "<leader>3",
            function()
                require("quarker").navigate(3)
            end,
            desc = "Quarker: Navigate to mark 3"
        },
        {
            "<leader>4",
            function()
                require("quarker").navigate(4)
            end,
            desc = "Quarker: Navigate to mark 4"
        },
        {
            "<leader>5",
            function()
                require("quarker").navigate(5)
            end,
            desc = "Quarker: Navigate to mark 5"
        },
        {
            "<leader>6",
            function()
                require("quarker").navigate(6)
            end,
            desc = "Quarker: Navigate to mark 6"
        },
        {
            "<leader>7",
            function()
                require("quarker").navigate(7)
            end,
            desc = "Quarker: Navigate to mark 7"
        },
        {
            "<leader>8",
            function()
                require("quarker").navigate(8)
            end,
            desc = "Quarker: Navigate to mark 8"
        },
        {
            "<leader>9",
            function()
                require("quarker").navigate(9)
            end,
            desc = "Quarker: Navigate to mark 9"
        },
        {
            "<leader>ga",
            function()
                require("quarker.ai").generate_commit_msg()
            end,
            desc = "Git: AI commit message"
        },
    },
    config = function()
        -- Create user commands
        vim.api.nvim_create_user_command("QuarkerMark", function()
            require("quarker").mark()
        end, { desc = "Mark current file with Quarker" })
        
        vim.api.nvim_create_user_command("QuarkerUnmark", function()
            require("quarker").unmark()
        end, { desc = "Unmark current file with Quarker" })
        
        vim.api.nvim_create_user_command("QuarkerToggle", function()
            require("quarker").show_marks_ui()
        end, { desc = "Toggle Quarker marks menu" })

        vim.api.nvim_create_user_command("QuarkerScopes", function()
            require("quarker").show_scopes_ui()
        end, { desc = "Manage Quarker scopes" })
        
        vim.api.nvim_create_user_command("QuarkerClear", function()
            require("quarker").clear_marks()
        end, { desc = "Clear all Quarker marks" })
        
        vim.api.nvim_create_user_command("QuarkerNavigate", function(opts)
            local index = tonumber(opts.args)
            if index then
                require("quarker").navigate(index)
            else
                vim.notify("Please provide a valid index", vim.log.levels.ERROR)
            end
        end, { 
            desc = "Navigate to Quarker mark by index",
            nargs = 1,
            complete = function()
                local marks = require("quarker").get_marks()
                local completions = {}
                for i = 1, #marks do
                    table.insert(completions, tostring(i))
                end
                return completions
            end
        })
    end
}
