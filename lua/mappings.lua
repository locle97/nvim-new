local map = vim.keymap.set

-- ── General ───────────────────────────────────────────────────────────
map("n", ";", ":", { noremap = true, silent = false, desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map("n", "<Esc>", "<cmd>noh<CR>", { desc = "Clear highlights" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "Copy whole file" })
map("n", "J", "mzJ`z", { desc = "Join line without jumping" })
map("n", "n", "nzzzv", { desc = "Next search result centered" })
map("n", "N", "Nzzzv", { desc = "Prev search result centered" })

-- ── Replace ───────────────────────────────────────────────────────────
map("n", "<leader>h", "yiw:%s/<C-r>\"//gI<Left><Left><Left>", { desc = "Replace current word" })
map("v", "<leader>h", "y:%s/<C-r>\"//gI<Left><Left><Left>",
    { noremap = true, silent = false, desc = "Replace selected text" })

-- ── Insert mode movement ──────────────────────────────────────────────
map("i", "<C-b>", "<ESC>^i", { desc = "Move beginning of line" })
map("i", "<C-e>", "<End>", { desc = "Move end of line" })
map("i", "<C-h>", "<Left>", { desc = "Move left" })
map("i", "<C-l>", "<Right>", { desc = "Move right" })
map("i", "<C-j>", "<Down>", { desc = "Move down" })
map("i", "<C-k>", "<Up>", { desc = "Move up" })

-- ── Window navigation ─────────────────────────────────────────────────
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })

-- ── Buffer navigation ─────────────────────────────────────────────────
map("n", "<tab>", "<cmd>bnext<CR>", { desc = "Buffer next" })
map("n", "<S-tab>", "<cmd>bprevious<CR>", { desc = "Buffer prev" })
map("n", "<leader>x", "<cmd>bdelete<CR>", { desc = "Buffer close" })
map("n", "<leader>bb", "<cmd>Telescope buffers<CR>", { desc = "Show buffers" })
map("n", "<leader>bo", function() require("utils").remove_other_buffers() end, { desc = "Delete other buffers" })

-- ── Comment ───────────────────────────────────────────────────────────
map("n", "<leader>/", "gcc", { desc = "Toggle comment", remap = true })
map("v", "<leader>/", "gc", { desc = "Toggle comment", remap = true })

-- ── Toggles ───────────────────────────────────────────────────────────
map("n", "<leader>n", "<cmd>set nu!<CR>", { desc = "Toggle line numbers" })
map("n", "<leader>rn", "<cmd>set rnu!<CR>", { desc = "Toggle relative numbers" })

-- ── Format ────────────────────────────────────────────────────────────
map({ "n", "x" }, "<leader>fm", function()
    require("conform").format({ lsp_fallback = true })
end, { desc = "Format file" })

-- ── File tree ─────────────────────────────────────────────────────────
map("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle file tree" })

-- ── Telescope ─────────────────────────────────────────────────────────
map("n", "<leader>fw", "<cmd>Telescope live_grep_args<CR>", { desc = "Live grep with args" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Find buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Help tags" })
map("n", "<leader>fo", "<cmd>Telescope oldfiles<CR>", { desc = "Old files" })
map("n", "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Fuzzy find in buffer" })
map("n", "<leader>cm", "<cmd>Telescope git_commits<CR>", { desc = "Git commits" })
map("n", "<leader>gs", "<cmd>Telescope git_status<CR>", { desc = "Git status" })
map("n", "<leader>fa", "<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
    { desc = "Find all files" })
map("n", "<leader>fp", "<cmd>Telescope projects<CR>", { desc = "Projects" })
map("n", "<leader>fF", "<cmd>Telescope find_files<CR>", { desc = "Find files (plain)" })
-- Quarker-enhanced find_files
map("n", "<C-p>", function() require("quarker.telescope_integration").find_files() end,
    { desc = "Find files (Quarker enhanced)" })
map("n", "<leader>ff", function() require("quarker.telescope_integration").find_files() end,
    { desc = "Find files (Quarker enhanced)" })

-- ── Terminal (toggleterm) ─────────────────────────────────────────────
map({ "n", "t" }, "<A-v>", function()
    require("toggleterm").toggle(1, nil, nil, "vertical")
end, { desc = "Toggle vertical terminal" })

map({ "n", "t" }, "<A-h>", function()
    require("toggleterm").toggle(2, nil, nil, "horizontal")
end, { desc = "Toggle horizontal terminal" })

map({ "n", "t" }, "<A-i>", function()
    require("toggleterm").toggle(3, nil, nil, "float")
end, { desc = "Toggle floating terminal" })

map("t", "<C-x>", "<C-\\><C-N>", { desc = "Terminal: exit terminal mode" })

-- ── LSP ───────────────────────────────────────────────────────────────
map("n", "<leader>ds", vim.diagnostic.setloclist, { desc = "LSP diagnostic loclist" })
map("n", "<leader>f", function() vim.diagnostic.open_float(nil, { border = "rounded" }) end,
    { desc = "Floating diagnostic" })
map("n", "<leader>q", function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end,
    { desc = "Buffer diagnostics" })
map("n", "<leader>fq", function() require("telescope.builtin").diagnostics() end,
    { desc = "Workspace diagnostics" })

map("n", "<C-y>", function() vim.lsp.buf.code_action() end, { desc = "LSP code action" })
map({ "n", "v" }, "<C-.>", function() vim.lsp.buf.code_action() end, { desc = "LSP code action" })
map("i", "<C-.>", function() vim.lsp.buf.code_action() end, { desc = "LSP code action" })

map("n", "gD", function() vim.lsp.buf.declaration() end, { noremap = true, silent = true, desc = "LSP declaration" })
map("n", "gd", function() vim.lsp.buf.definition() end, { noremap = true, silent = true, desc = "LSP definition" })
map("n", "K", function() vim.lsp.buf.hover() end, { desc = "LSP hover" })
map("n", "gi", function() require("telescope.builtin").lsp_implementations() end,
    { noremap = true, silent = true, desc = "LSP implementation" })
map("n", "gr", function() require("telescope.builtin").lsp_references() end,
    { noremap = true, silent = true, desc = "LSP references" })
map("n", "go", function() require("telescope.builtin").lsp_document_symbols() end,
    { noremap = true, silent = true, desc = "LSP document symbols" })

map("n", "<F2>", function() vim.lsp.buf.rename() end, { desc = "LSP rename" })

map("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, { desc = "LSP add workspace folder" })
map("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, { desc = "LSP remove workspace folder" })
map("n", "<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
end, { desc = "LSP list workspace folders" })

-- ── Git ───────────────────────────────────────────────────────────────
map("n", "<leader>gl", ":LazyGit<CR>", { desc = "Open LazyGit" })
map("n", "<leader>ge", function() require("utils").toggle_git_explorer() end, { desc = "Toggle git explorer" })
map("n", "<leader>gc", function() require("utils").git_commit() end, { desc = "Git commit" })

local gitsigns = require("gitsigns")

map("n", "]c", function()
    if vim.wo.diff then vim.cmd.normal({ "]c", bang = true })
    else gitsigns.nav_hunk("next") end
end)
map("n", "[c", function()
    if vim.wo.diff then vim.cmd.normal({ "[c", bang = true })
    else gitsigns.nav_hunk("prev") end
end)
map("n", "<leader>gs", gitsigns.stage_hunk)
map("n", "<leader>gr", gitsigns.reset_hunk)
map("v", "<leader>gs", function() gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end)
map("v", "<leader>gr", function() gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end)
map("n", "<leader>gd", gitsigns.toggle_deleted, { desc = "Toggle git deleted" })

-- ── Tmux ──────────────────────────────────────────────────────────────
map("n", "<C-h>", "<cmd>TmuxNavigateLeft<CR>")
map("n", "<C-j>", "<cmd>TmuxNavigateDown<CR>")
map("n", "<C-k>", "<cmd>TmuxNavigateUp<CR>")
map("n", "<C-l>", "<cmd>TmuxNavigateRight<CR>")
map("n", "<C-\\>", "<cmd>TmuxNavigatePrevious<CR>")

-- ── Utilities ─────────────────────────────────────────────────────────
map("n", "<leader>y", function() require("utils").copy_relative_path() end, { desc = "Copy relative path" })
map("v", "<leader>y", function() require("utils").copy_relative_path_with_lines() end,
    { desc = "Copy relative path with lines" })
