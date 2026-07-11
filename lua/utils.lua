local M = {}

M.remove_other_buffers = function()
    local current_buf = vim.api.nvim_get_current_buf()
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        if buf ~= current_buf and vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

-- Get the scope (git root or CWD)
local function get_scope()
    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    if vim.v.shell_error == 0 and git_root and git_root ~= "" then
        return git_root
    else
        return vim.fn.getcwd()
    end
end

-- Get relative path from scope
local function get_relative_path(filepath, scope)
    if filepath:sub(1, #scope) == scope then
        local relative = filepath:sub(#scope + 1)
        if relative:sub(1, 1) == "/" then
            relative = relative:sub(2)
        end
        return relative
    end
    return filepath
end

-- Copy relative path to clipboard
M.copy_relative_path = function()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to copy path", vim.log.levels.WARN)
        return
    end
    local scope = get_scope()
    local relative_path = get_relative_path(filepath, scope)
    vim.fn.setreg("+", relative_path)
    vim.notify("Copied: " .. relative_path, vim.log.levels.INFO)
end

-- Copy relative path with line range to clipboard (for visual selection)
M.copy_relative_path_with_lines = function()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        vim.notify("No file to copy path", vim.log.levels.WARN)
        return
    end
    local scope = get_scope()
    local relative_path = get_relative_path(filepath, scope)
    local l1 = vim.fn.line("v")
    local l2 = vim.fn.line(".")
    local start_line = math.min(l1, l2)
    local end_line = math.max(l1, l2)
    local result = relative_path .. " L" .. start_line .. "-" .. end_line
    vim.fn.setreg("+", result)
    vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

-- Git panel: nvim-tree showing only git-dirty files as a side panel
do
    local git_panel_open = false
    local events_subscribed = false

    M.toggle_git_explorer = function()
        local api = require("nvim-tree.api")
        local view = require("nvim-tree.view")

        if not events_subscribed then
            events_subscribed = true
            api.events.subscribe(api.events.Event.TreeClose, function()
                if git_panel_open then
                    git_panel_open = false
                    require("nvim-tree").setup(vim.deepcopy(require("configs.nvimtree")))
                end
            end)
        end

        if git_panel_open then
            api.tree.close()
            return
        end

        if view.is_visible() then
            api.tree.close()
        end

        local opts = vim.tbl_deep_extend("force", vim.deepcopy(require("configs.nvimtree")), {
            view = {
                side = "left",
                width = 40,
                float = { enable = false },
            },
            filters = {
                git_clean = true,
            },
        })

        require("nvim-tree").setup(opts)
        git_panel_open = true
        api.tree.open()
    end
end

-- Codediff review mode: a persistent diff session against HEAD that follows
-- whichever file you look at, instead of diffing a single buffer once.
-- codediff renders into its own tab; view.update() re-targets that tab in place,
-- which is how the plugin's own explorer switches files.
do
    local diff_tab = nil
    local origin_tab = nil
    local augroup = nil
    -- The buffer whose diff we are currently trying to show. Switching files
    -- again supersedes any in-flight render for the previous one.
    local pending_buf = nil

    -- Only real, on-disk files can be diffed: skips nvim-tree, terminals,
    -- codediff's own scratch/virtual buffers, and unsaved buffers.
    local function is_reviewable(buf)
        if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
            return false
        end
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "" or name:match("^%a+://") then
            return false
        end
        return vim.fn.filereadable(name) == 1
    end

    local function stop()
        if augroup then
            pcall(vim.api.nvim_del_augroup_by_id, augroup)
            augroup = nil
        end
        local tab = diff_tab
        diff_tab = nil
        pending_buf = nil
        if tab and vim.api.nvim_tabpage_is_valid(tab) then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd("tabclose")
        end
        if origin_tab and vim.api.nvim_tabpage_is_valid(origin_tab) then
            vim.api.nvim_set_current_tabpage(origin_tab)
        end
        origin_tab = nil
    end

    -- Point the diff tab at `buf`. Resolving a file is async, so a switch that
    -- lands while an earlier one is still resolving supersedes it.
    local function apply(buf, session_config)
        if pending_buf ~= buf or not (diff_tab and vim.api.nvim_tabpage_is_valid(diff_tab)) then
            return
        end

        local lifecycle = require("codediff.ui.lifecycle")
        local session = lifecycle.get_session(diff_tab)
        if not session or session.modified_path == session_config.modified_path then
            return
        end

        pcall(require("codediff.ui.view").update, diff_tab, session_config, true)
    end

    -- Re-render the diff tab for `buf`. Errors (file outside a repo, unresolvable
    -- revision) leave the previous diff on screen rather than nagging on every
    -- buffer switch.
    local function show(buf)
        local ok, git = pcall(require, "codediff.core.git")
        if not ok then
            return
        end
        pending_buf = buf
        local file = vim.api.nvim_buf_get_name(buf)

        git.get_git_root(file, function(root_err, git_root)
            if root_err then
                return
            end
            local relative_path = git.get_relative_path(file, git_root)

            git.resolve_revision("HEAD", git_root, function(rev_err, commit_hash)
                if rev_err then
                    return
                end
                -- Follow renames: the path at HEAD may differ from the current one.
                git.resolve_path_at_revision(commit_hash, git_root, relative_path, function(_, original_path)
                    vim.schedule(function()
                        apply(buf, {
                            mode = "standalone",
                            git_root = git_root,
                            original_path = original_path or relative_path,
                            modified_path = relative_path,
                            original_revision = commit_hash,
                            modified_revision = "WORKING",
                        })
                    end)
                end)
            end)
        end)
    end

    local function watch()
        augroup = vim.api.nvim_create_augroup("CodediffReviewMode", { clear = true })

        vim.api.nvim_create_autocmd("BufEnter", {
            group = augroup,
            callback = function(args)
                if not (diff_tab and vim.api.nvim_tabpage_is_valid(diff_tab)) then
                    stop()
                elseif is_reviewable(args.buf) then
                    show(args.buf)
                end
            end,
        })

        -- Closing the diff tab by hand (:q) leaves the mode on with nothing to
        -- render into, so tear it down instead of getting stuck.
        vim.api.nvim_create_autocmd("TabClosed", {
            group = augroup,
            callback = function()
                if not (diff_tab and vim.api.nvim_tabpage_is_valid(diff_tab)) then
                    stop()
                end
            end,
        })
    end

    -- :CodeDiff is async, so the diff tab does not exist when the command
    -- returns. Poll briefly for the tab it created (any tab that is new since
    -- the command was issued and owns a codediff session).
    local function capture(known, attempts)
        local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
        if not ok then
            return
        end
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
            if not known[tab] and lifecycle.get_session(tab) then
                diff_tab = tab
                watch()
                -- BufEnter only fires on entering a buffer, so any file switched
                -- to before the watcher went live would never render. Reconcile
                -- with whatever is on screen now.
                local buf = vim.api.nvim_get_current_buf()
                if is_reviewable(buf) then
                    show(buf)
                end
                return
            end
        end
        if attempts < 60 then
            vim.defer_fn(function() capture(known, attempts + 1) end, 50)
        end
    end

    M.toggle_file_diff = function()
        if diff_tab and vim.api.nvim_tabpage_is_valid(diff_tab) then
            stop()
            return
        end

        if not is_reviewable(vim.api.nvim_get_current_buf()) then
            vim.notify("Open a file to diff it", vim.log.levels.WARN)
            return
        end

        local known = {}
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
            known[tab] = true
        end
        origin_tab = vim.api.nvim_get_current_tabpage()

        vim.cmd("CodeDiff file HEAD")
        capture(known, 0)
    end
end

-- Git commit with dressing input
M.git_commit = function()
    vim.ui.input({ prompt = "Commit message: " }, function(msg)
        if not msg or msg == "" then
            return
        end
        local output = vim.fn.systemlist({ "git", "commit", "-m", msg, "--no-verify" })
        if vim.v.shell_error == 0 then
            vim.notify("Committed: " .. msg, vim.log.levels.INFO)
        else
            vim.notify(table.concat(output, "\n"), vim.log.levels.ERROR)
        end
    end)
end

return M
