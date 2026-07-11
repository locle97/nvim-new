-- The <leader><leader> panel: one float, two tabs (Marks, Git Changes).
--
-- The panel owns the window, the tab bar and <Tab>; it knows nothing about what a
-- tab contains. Each tab is a module exposing title/footer/render/keymaps and an
-- optional on_leave, and gets its own buffer, so per-tab keymaps, 'modifiable' and
-- cursor position are the buffer's business rather than something to save and
-- restore on every switch.
local float = require("quarker.ui.float")

local M = {}

local WIN_TYPE = "panel"

local function setup_highlights()
    vim.api.nvim_set_hl(0, "QuarkerTabActive", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "QuarkerTabInactive", { link = "Comment", default = true })
end

function M.open()
    setup_highlights()

    local tabs = {
        require("quarker.ui.marks"),
        require("quarker.ui.git"),
    }

    local bufs = {}
    for i in ipairs(tabs) do
        -- "hide", not "wipe": the inactive tab's buffer is not displayed anywhere
        -- and must survive until the panel closes.
        bufs[i] = float.create_buf({ bufhidden = "hide" })
    end

    local _, winid = float.create_float_win({
        width_ratio = 0.6,
        height_ratio = 0.7,
        win_type = WIN_TYPE,
        bufnr = bufs[1],
    })

    local active = 1
    local ctxs = {}
    local closing = false

    -- The tab bar lives in the border, not the buffer: the marks buffer is editable,
    -- and a tab bar line inside it is a line you can delete or reorder into.
    local function render_border()
        local chunks = {}
        for i, tab in ipairs(tabs) do
            if i > 1 then
                table.insert(chunks, { "│", "FloatBorder" })
            end
            table.insert(chunks, {
                string.format("  %s  ", tab.title(ctxs[i])),
                i == active and "QuarkerTabActive" or "QuarkerTabInactive",
            })
        end

        float.set_border(winid, chunks, string.format(" %s ", tabs[active].footer()))
    end

    local function close()
        if closing then
            return
        end
        closing = true

        local tab = tabs[active]
        if tab.on_leave then
            tab.on_leave(ctxs[active])
        end

        float.close_float_win(winid)

        for _, bufnr in ipairs(bufs) do
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.api.nvim_buf_delete(bufnr, { force = true })
            end
        end
    end

    for i, tab in ipairs(tabs) do
        ctxs[i] = {
            bufnr = bufs[i],
            winid = winid,
            close = close,
            -- Redraw this tab and the tab bar: a tab's own action (staging a file,
            -- marking one) can change what either tab's label says.
            refresh = function()
                if not vim.api.nvim_win_is_valid(winid) then
                    return
                end
                if active == i then
                    tab.render(ctxs[i])
                end
                render_border()
            end,
        }
    end

    local function activate(index)
        if index == active or not vim.api.nvim_win_is_valid(winid) then
            return
        end

        local previous = tabs[active]
        if previous.on_leave then
            previous.on_leave(ctxs[active])
        end

        active = index
        vim.api.nvim_win_set_buf(winid, bufs[active])
        tabs[active].render(ctxs[active])
        render_border()
    end

    local function next_tab()
        activate(active % #tabs + 1)
    end

    for i, tab in ipairs(tabs) do
        local keymaps = tab.keymaps(ctxs[i])
        table.insert(keymaps, { mode = "n", key = "<Tab>", callback = next_tab, desc = "Switch tab" })
        table.insert(keymaps, { mode = "n", key = "q", callback = close, desc = "Close" })
        table.insert(keymaps, { mode = "n", key = "<Esc>", callback = close, desc = "Close" })
        float.set_float_keymaps(bufs[i], keymaps)
    end

    -- Closing the window any other way (:q, another float taking the slot) still has
    -- to sync the marks buffer and take the hidden buffers with it.
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winid),
        once = true,
        callback = function()
            vim.schedule(close)
        end,
    })

    tabs[active].render(ctxs[active])
    render_border()
end

return M
