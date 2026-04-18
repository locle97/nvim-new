local opt = vim.opt
local o = vim.o
local g = vim.g

-- ── General ──────────────────────────────────────────────────────────
o.laststatus = 3
o.showmode = false
o.clipboard = "unnamedplus"
o.mouse = "a"
o.timeoutlen = 400
o.undofile = true
o.updatetime = 250

-- ── Appearance ───────────────────────────────────────────────────────
o.cursorline = true
o.cursorlineopt = "both"
o.number = true
o.numberwidth = 2
o.ruler = false
o.signcolumn = "yes"
opt.fillchars = { eob = " " }
opt.shortmess:append("sI")
opt.colorcolumn = "80"
opt.relativenumber = true

-- ── Indenting ─────────────────────────────────────────────────────────
o.expandtab = true
o.shiftwidth = 4
o.smartindent = true
o.tabstop = 4
o.softtabstop = 4
o.wrap = false

-- ── Search ───────────────────────────────────────────────────────────
o.ignorecase = true
o.smartcase = true

-- ── Splits ───────────────────────────────────────────────────────────
o.splitbelow = true
o.splitright = true

-- ── Wrapping ──────────────────────────────────────────────────────────
opt.whichwrap:append("<>[]hl")

-- ── Disable unused providers ──────────────────────────────────────────
g.loaded_node_provider = 0
g.loaded_python3_provider = 0
g.loaded_perl_provider = 0
g.loaded_ruby_provider = 0

-- ── Mason binaries on PATH ───────────────────────────────────────────
local sep = vim.fn.has("win32") ~= 0 and "\\" or "/"
local delim = vim.fn.has("win32") ~= 0 and ";" or ":"
vim.env.PATH = table.concat({ vim.fn.stdpath("data"), "mason", "bin" }, sep) .. delim .. vim.env.PATH

-- ── Custom filetypes ──────────────────────────────────────────────────
vim.filetype.add({
    extension = {
        cql = "cypher",
        cypher = "cypher",
        resx = "xml",
    },
})
