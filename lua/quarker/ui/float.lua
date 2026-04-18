local M = {}

-- State to track open windows and prevent duplicates
M.state = {
    marks_win = nil,
    scopes_win = nil,
    context_win = nil,
}

-- Get window configuration for centered floating window
-- @param width_ratio number Width as ratio of screen (0.0-1.0)
-- @param height_ratio number Height as ratio of screen (0.0-1.0)
-- @param title string Optional window title
-- @param footer string Optional window footer
-- @return table Window configuration for nvim_open_win
function M.get_window_config(width_ratio, height_ratio, title, footer)
    local screen_w = vim.opt.columns:get()
    local screen_h = vim.opt.lines:get() - vim.opt.cmdheight:get()

    local window_w = screen_w * width_ratio
    local window_h = screen_h * height_ratio
    local window_w_int = math.floor(window_w)
    local window_h_int = math.floor(window_h)

    local center_x = (screen_w - window_w) / 2
    local center_y = ((vim.opt.lines:get() - window_h) / 2) - vim.opt.cmdheight:get()

    local config = {
        border = "rounded",
        relative = "editor",
        row = center_y,
        col = center_x,
        width = window_w_int,
        height = window_h_int,
        style = "minimal",
    }

    if title then
        config.title = title
        config.title_pos = "center"
    end

    if footer then
        config.footer = footer
        config.footer_pos = "center"
    end

    return config
end

-- Create a floating window with buffer
-- @param opts table Options: width_ratio, height_ratio, title, footer, win_type
-- @return number, number bufnr, winid
function M.create_float_win(opts)
    opts = opts or {}
    local width_ratio = opts.width_ratio or 0.6
    local height_ratio = opts.height_ratio or 0.7
    local title = opts.title or ""
    local footer = opts.footer
    local win_type = opts.win_type or "marks" -- "marks" or "scopes" or "context"

    -- Close existing window of the same type if open
    if win_type == "marks" and M.state.marks_win then
        M.close_float_win(M.state.marks_win)
        M.state.marks_win = nil
    elseif win_type == "scopes" and M.state.scopes_win then
        M.close_float_win(M.state.scopes_win)
        M.state.scopes_win = nil
    elseif win_type == "context" and M.state.context_win then
        M.close_float_win(M.state.context_win)
        M.state.context_win = nil
    end

    -- Create buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "quarker")

    -- Get window config and open window
    local win_config = M.get_window_config(width_ratio, height_ratio, title, footer)
    local winid = vim.api.nvim_open_win(bufnr, true, win_config)

    -- Set window options
    vim.api.nvim_win_set_option(winid, "cursorline", true)
    vim.api.nvim_win_set_option(winid, "wrap", false)
    vim.api.nvim_win_set_option(winid, "number", false)
    vim.api.nvim_win_set_option(winid, "relativenumber", false)

    -- Store window reference
    if win_type == "marks" then
        M.state.marks_win = winid
    elseif win_type == "scopes" then
        M.state.scopes_win = winid
    elseif win_type == "context" then
        M.state.context_win = winid
    end

    -- Setup autocmd for cleanup
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        once = true,
        callback = function()
            if win_type == "marks" then
                M.state.marks_win = nil
            elseif win_type == "scopes" then
                M.state.scopes_win = nil
            elseif win_type == "context" then
                M.state.context_win = nil
            end
        end,
    })

    return bufnr, winid
end

-- Close a floating window safely
-- @param winid number Window ID to close
function M.close_float_win(winid)
    if winid and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
    end
end

-- Render lines to buffer with highlights
-- @param bufnr number Buffer number
-- @param lines table Array of lines to render
-- @param highlights table Array of highlight specs {line, col_start, col_end, hl_group}
function M.render_lines(bufnr, lines, highlights)
    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Set lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- Apply highlights
    local ns_id = vim.api.nvim_create_namespace("quarker_float")
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    if highlights then
        for _, hl in ipairs(highlights) do
            vim.api.nvim_buf_add_highlight(
                bufnr,
                ns_id,
                hl.hl_group,
                hl.line - 1, -- 0-indexed
                hl.col_start,
                hl.col_end
            )
        end
    end
end

-- Set keymaps for buffer
-- @param bufnr number Buffer number
-- @param mappings table Array of {mode, key, callback, desc}
function M.set_float_keymaps(bufnr, mappings)
    for _, mapping in ipairs(mappings) do
        vim.keymap.set(
            mapping.mode or "n",
            mapping.key,
            mapping.callback,
            { buffer = bufnr, nowait = true, silent = true, desc = mapping.desc }
        )
    end
end

return M
