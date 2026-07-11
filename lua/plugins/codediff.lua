return {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {
        diff = {
            layout = "inline",
        }
    },
    config = function(_, opts)
        require("codediff").setup(opts)
    end,
}
