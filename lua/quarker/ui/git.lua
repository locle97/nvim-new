-- The Git Changes tab of the Quarker panel: the repository's dirty files, split
-- into Changes and Staged Changes the way git itself models them.
local float = require("quarker.ui.float")
local git = require("quarker.git")

local M = {}

-- Status letter -> highlight. nvim-tree's git groups are already themed, so the
-- colors follow the colorscheme instead of being hardcoded here.
local STATUS_HL = {
    M = "NvimTreeGitDirty",
    A = "NvimTreeGitStaged",
    R = "NvimTreeGitStaged",
    C = "NvimTreeGitStaged",
    D = "NvimTreeGitDeleted",
    U = "NvimTreeGitNew",
}

local function get_filetype_icon(filename)
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
        local icon, hl_group = devicons.get_icon(filename, vim.fn.fnamemodify(filename, ":e"), { default = true })
        return icon or "", hl_group
    end
    return "", nil
end

-- Read git state into ctx. Everything else in this module renders from ctx.status
-- and ctx.entries, so the two never disagree about what is on screen.
local function load(ctx)
    local status, err = git.status()
    ctx.status = status
    ctx.error = err
    return status
end

local function ensure_loaded(ctx)
    if not ctx.status and not ctx.error then
        load(ctx)
    end
    return ctx.status
end

-- Build one entry line: "  <icon> <name>  <dir>" with the status letter flush right.
local function entry_line(entry, icon, width)
    local left = string.format("  %s %s", icon, entry.name)
    if entry.dir ~= "" then
        left = left .. " " .. entry.dir
    end

    -- Pad in display cells (the icon is wider than its byte length) so the status
    -- letter lands on the right edge regardless of the icon or unicode in the path.
    local pad = width - vim.fn.strdisplaywidth(left) - 2
    if pad < 1 then
        pad = 1
    end

    return left .. string.rep(" ", pad) .. entry.status
end

local function render_section(ctx, state, label, entries, width)
    table.insert(state.lines, string.format("%s (%d)", label, #entries))
    table.insert(state.highlights, {
        line = #state.lines,
        col_start = 0,
        col_end = -1,
        hl_group = "Title",
    })

    for _, entry in ipairs(entries) do
        local icon, icon_hl = get_filetype_icon(entry.name)
        local line = entry_line(entry, icon, width)
        table.insert(state.lines, line)

        local line_nr = #state.lines
        ctx.entries[line_nr] = { entry = entry, staged = label == "Staged Changes" }

        local icon_start = 2
        local icon_end = icon_start + string.len(icon)
        local name_end = icon_end + 1 + string.len(entry.name)

        if icon_hl and icon ~= "" then
            table.insert(state.highlights, {
                line = line_nr,
                col_start = icon_start,
                col_end = icon_end,
                hl_group = icon_hl,
            })
        end

        if entry.dir ~= "" then
            table.insert(state.highlights, {
                line = line_nr,
                col_start = name_end + 1,
                col_end = name_end + 1 + string.len(entry.dir),
                hl_group = "Comment",
            })
        end

        table.insert(state.highlights, {
            line = line_nr,
            col_start = string.len(line) - 1,
            col_end = -1,
            hl_group = STATUS_HL[entry.status] or "Comment",
        })
    end
end

function M.title(ctx)
    local status = ensure_loaded(ctx)
    if not status then
        return "Git Changes"
    end
    return string.format("Git Changes (%d)", #status.unstaged + #status.staged)
end

function M.footer()
    return "<CR> open   d diff   s stage   m mark   r refresh   <Tab> marks"
end

function M.render(ctx)
    ctx.entries = {}

    local status = ensure_loaded(ctx)

    if not status then
        float.render_lines(ctx.bufnr, { ctx.error or "Not a git repository" }, {
            { line = 1, col_start = 0, col_end = -1, hl_group = "Comment" },
        })
        vim.api.nvim_buf_set_option(ctx.bufnr, "modifiable", false)
        return
    end

    local width = vim.api.nvim_win_get_width(ctx.winid)
    local state = { lines = {}, highlights = {} }

    render_section(ctx, state, "Changes", status.unstaged, width)
    render_section(ctx, state, "Staged Changes", status.staged, width)

    float.render_lines(ctx.bufnr, state.lines, state.highlights)
    vim.api.nvim_buf_set_option(ctx.bufnr, "modifiable", false)
end

function M.keymaps(ctx)
    local quarker = require("quarker")

    -- The entry under the cursor, or nil on a section header / the empty state.
    local function current()
        local line = vim.api.nvim_win_get_cursor(ctx.winid)[1]
        local item = ctx.entries[line]
        if not item then
            return nil
        end
        return item.entry, item.staged
    end

    local function abs_path(entry)
        return quarker.get_scope() .. "/" .. entry.path
    end

    -- Redraw from git, keeping the cursor where it was but inside the new list.
    local function refresh()
        local line = vim.api.nvim_win_get_cursor(ctx.winid)[1]
        load(ctx)
        ctx.refresh()
        local count = vim.api.nvim_buf_line_count(ctx.bufnr)
        pcall(vim.api.nvim_win_set_cursor, ctx.winid, { math.min(line, count), 0 })
    end

    local function open()
        local entry = current()
        if not entry then
            return
        end

        local path = abs_path(entry)
        if vim.fn.filereadable(path) == 0 then
            vim.notify("File no longer on disk: " .. entry.path, vim.log.levels.WARN)
            return
        end

        ctx.close()
        vim.cmd("edit " .. vim.fn.fnameescape(path))
    end

    local function diff()
        local entry = current()
        if not entry then
            return
        end

        local path = abs_path(entry)
        if vim.fn.filereadable(path) == 0 then
            vim.notify("File no longer on disk: " .. entry.path, vim.log.levels.WARN)
            return
        end

        ctx.close()
        vim.cmd("edit " .. vim.fn.fnameescape(path))

        -- An untracked file has no HEAD version to diff against, so opening it is
        -- all that can be done.
        if entry.status == "U" then
            vim.notify("Untracked file: nothing at HEAD to diff against", vim.log.levels.WARN)
            return
        end

        vim.cmd("CodeDiff file HEAD")
    end

    -- Direction comes from the section the entry is in, so `s` reads as a toggle.
    local function stage()
        local entry, staged = current()
        if not entry then
            return
        end

        local ok, err
        if staged then
            ok, err = git.unstage(entry.path)
        else
            ok, err = git.stage(entry.path)
        end

        if not ok then
            vim.notify(err or "git failed", vim.log.levels.ERROR)
        end

        refresh()
    end

    local function mark()
        local entry = current()
        if not entry then
            return
        end

        if quarker.mark_file(abs_path(entry)) then
            vim.notify("Marked: " .. entry.path, vim.log.levels.INFO)
        else
            vim.notify("Already marked: " .. entry.path, vim.log.levels.INFO)
        end

        -- The marks tab renders from Quarker on activation, so only the tab bar
        -- count needs to catch up here.
        ctx.refresh()
    end

    return {
        { mode = "n", key = "<CR>", callback = open, desc = "Open file" },
        { mode = "n", key = "d", callback = diff, desc = "Diff against HEAD" },
        { mode = "n", key = "s", callback = stage, desc = "Stage/unstage file" },
        { mode = "n", key = "m", callback = mark, desc = "Mark file in Quarker" },
        { mode = "n", key = "r", callback = refresh, desc = "Refresh git status" },
    }
end

return M
