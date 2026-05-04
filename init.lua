vim.g.mapleader = " "
vim.g.base46_cache = vim.fn.stdpath("data") .. "/base46/"

-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({ { import = "plugins" } }, require("configs.lazy"))

-- Load NvChad/base46 highlight cache (built by the base46 plugin's `build` step).
if vim.fn.isdirectory(vim.g.base46_cache) == 1 then
    for _, v in ipairs(vim.fn.readdir(vim.g.base46_cache)) do
        dofile(vim.g.base46_cache .. v)
    end
end

require("options")
require("autocmds")
require("commands.notes")
require("commands.live-grep-quick")

vim.schedule(function()
    require("mappings")
end)
