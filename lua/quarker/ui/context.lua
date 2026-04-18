local float = require("quarker.ui.float")
local context = require("quarker.context")
local M = {}

-- State for tracking AI operations
local ai_state = {
    running = false,
    bufnr = nil,
    winid = nil,
    original_content = nil,
    spinner_idx = 1,
    timer = nil,
    message = nil,
    preview = nil,
}

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- ============================================================================
-- Loading Indicator
-- ============================================================================

local function show_loading(bufnr, message, preview)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    ai_state.spinner_idx = (ai_state.spinner_idx % #SPINNER_FRAMES) + 1
    local spinner = SPINNER_FRAMES[ai_state.spinner_idx]

    local lines = {
        "",
        string.format("  %s %s", spinner, message or "AI is working..."),
        "",
    }

    if preview and preview ~= "" then
        table.insert(lines, "  " .. preview)
        table.insert(lines, "")
    end

    table.insert(lines, "  Please wait...")
    table.insert(lines, "")

    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

local function start_loading_animation(bufnr, message)
    ai_state.running = true
    ai_state.spinner_idx = 1
    ai_state.message = message
    ai_state.preview = nil

    -- Stop existing timer if any
    if ai_state.timer then
        vim.fn.timer_stop(ai_state.timer)
    end

    -- Start spinner animation
    ai_state.timer = vim.fn.timer_start(100, function()
        if ai_state.running and vim.api.nvim_buf_is_valid(bufnr) then
            show_loading(bufnr, ai_state.message, ai_state.preview)
        else
            if ai_state.timer then
                vim.fn.timer_stop(ai_state.timer)
                ai_state.timer = nil
            end
        end
    end, { ["repeat"] = -1 })

    show_loading(bufnr, message, nil)
end

local function stop_loading_animation()
    ai_state.running = false
    if ai_state.timer then
        vim.fn.timer_stop(ai_state.timer)
        ai_state.timer = nil
    end
end

-- ============================================================================
-- AI Integration
-- ============================================================================

local function run_ai_with_loading(bufnr, winid, backend, prompt, message, callback)
    -- Save original content
    ai_state.original_content = context.get_content()
    ai_state.bufnr = bufnr
    ai_state.winid = winid

    -- Start loading animation
    start_loading_animation(bufnr, message)

    -- Write prompt to temp file
    local tmpfile = vim.fn.tempname()
    local f = io.open(tmpfile, "w")
    if not f then
        stop_loading_animation()
        vim.notify("Failed to create temp file", vim.log.levels.ERROR)
        return
    end
    f:write(prompt)
    f:close()

    -- Build command based on backend
    local full_cmd
    if backend == "claude" then
        full_cmd = string.format("cat '%s' | claude --print 2>&1", tmpfile)
    elseif backend == "cursor-agent" then
        full_cmd = string.format("cat '%s' | cursor-agent 2>&1", tmpfile)
    else
        full_cmd = string.format("cat '%s' | copilot chat --no-interactive 2>&1", tmpfile)
    end

    local output_lines = {}

    vim.fn.jobstart(full_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        table.insert(output_lines, line)
                        -- Update preview with last line
                        if ai_state.running then
                            local preview = line:sub(1, 60)
                            if #line > 60 then
                                preview = preview .. "..."
                            end
                            ai_state.preview = preview
                        end
                    end
                end
            end
        end,
        on_exit = function(_, code)
            os.remove(tmpfile)
            stop_loading_animation()

            vim.schedule(function()
                if code == 0 and #output_lines > 0 then
                    local result = table.concat(output_lines, "\n")
                    result = result:gsub("^%s+", ""):gsub("%s+$", "")
                    if callback then
                        callback(result)
                    end
                else
                    vim.notify("AI command failed", vim.log.levels.ERROR)
                    -- Restore original content
                    if ai_state.original_content then
                        reload_content(bufnr, ai_state.original_content)
                    end
                end
            end)
        end,
    })
end

-- Reload content into buffer
local function reload_content(bufnr, content)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local lines = {}
    if content and content ~= "" then
        for line in content:gmatch("([^\n]*)\n?") do
            table.insert(lines, line)
        end
        if #lines > 0 and lines[#lines] == "" then
            table.remove(lines)
        end
    end

    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, "modified", false)
end

-- Forward declare for use in callbacks
local function reload_content_forward(bufnr, content)
    reload_content(bufnr, content)
end

-- ============================================================================
-- Prompt Builders (copied from ai.lua for self-contained module)
-- ============================================================================

local function get_marked_files_content()
    local quarker = require("quarker")
    local marks = quarker.get_marks()
    local base_scope = quarker.get_scope()

    local files = {}
    for _, mark in ipairs(marks) do
        local filepath = base_scope .. "/" .. mark.path
        if vim.fn.filereadable(filepath) == 1 then
            local file = io.open(filepath, "r")
            if file then
                local content = file:read("*all")
                file:close()
                table.insert(files, {
                    path = mark.path,
                    content = content,
                })
            end
        end
    end
    return files
end

local function build_generate_context_prompt(files, seed_prompt, existing_context)
    local prompt = [[You are analyzing a codebase to generate development context.

## Instructions
Generate a structured markdown context document. For each section, add a confidence indicator:
- ✅ from code - directly observed in the code
- ⚠️ inferred - reasonable assumption based on patterns
- ❓ unknown - needs clarification

## Marked Files
]]

    for _, file in ipairs(files) do
        prompt = prompt .. string.format("\n### %s\n```\n%s\n```\n", file.path, file.content)
    end

    if existing_context and existing_context ~= "" then
        prompt = prompt .. "\n## Existing Context (update/enhance this)\n" .. existing_context .. "\n"
    end

    if seed_prompt and seed_prompt ~= "" then
        prompt = prompt .. "\n## User Notes\n" .. seed_prompt .. "\n"
    end

    prompt = prompt .. [[

## Output Format
Generate markdown with these sections:
1. **Overview** - What this scope/feature does
2. **Code Map** - Key files and their purposes
3. **Architecture** - How components connect
4. **Sharp Edges** - Gotchas, edge cases, things to watch out for
5. **Decisions** - Why things are done this way

Mark each statement with confidence: ✅ ⚠️ or ❓
Only output the markdown, no extra commentary.
]]

    return prompt
end

local function build_refresh_context_prompt(diff, existing_context)
    local prompt = [[You are updating development context based on recent code changes.

## Git Diff
```diff
]] .. diff .. [[
```

## Existing Context
]] .. existing_context .. [[

## Instructions
Update ONLY these sections based on the diff:
1. **Code Map** - Add/remove/update files mentioned in diff
2. **Sharp Edges** - Note any new edge cases visible in the changes
3. **Decisions** - APPEND any new decisions visible (don't remove old ones)

Keep confidence markers (✅ ⚠️ ❓). New items from diff should be ✅.
Return the complete updated context document. Only output the markdown, no extra commentary.
]]

    return prompt
end

local function build_feature_note_prompt(name, files)
    local prompt = string.format([[You are documenting a feature called "%s".

## Instructions
Generate a feature note document for AI-assisted development.

## Relevant Files
]], name)

    for _, file in ipairs(files) do
        prompt = prompt .. string.format("\n### %s\n```\n%s\n```\n", file.path, file.content)
    end

    prompt = prompt .. [[

## Output Format
Generate markdown with:
1. **Purpose** - What this feature does (1-2 sentences)
2. **Entry Points** - Where the feature starts (files, functions)
3. **Data Flow** - How data moves through the feature
4. **Dependencies** - What this feature relies on
5. **Testing Notes** - How to test/verify this feature
6. **TODOs** - Obvious improvements or missing pieces

Be concise. This is a working note, not documentation.
Only output the markdown, no extra commentary.
]]

    return prompt
end

-- ============================================================================
-- Main Context UI
-- ============================================================================

-- Help bar text
local HELP_BAR = " <leader>g Generate │ <leader>r Refresh │ <leader>f Feature │ x Export │ :w Save │ q Close "

function M.show_context()
    local quarker = require("quarker")
    local ai = require("quarker.ai")
    local scope_name = quarker.get_active_scope_name()
    local filepath = context.get_context_path()

    local title = string.format(" Context: %s ", scope_name)

    -- Create floating window with footer
    local bufnr, winid = float.create_float_win({
        width_ratio = 0.75,
        height_ratio = 0.85,
        title = title,
        win_type = "context",
        footer = HELP_BAR,
    })

    -- Load content
    local content = context.get_content()
    local lines = {}
    if content ~= "" then
        for line in content:gmatch("([^\n]*)\n?") do
            table.insert(lines, line)
        end
        if #lines > 0 and lines[#lines] == "" then
            table.remove(lines)
        end
    end

    -- Set buffer content
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, "modified", false)

    -- Set filetype for syntax highlighting
    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")

    -- Make buffer writable
    vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    vim.api.nvim_buf_set_name(bufnr, "quarker://context/" .. scope_name)

    -- Save on write
    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        callback = function()
            if ai_state.running then
                vim.notify("AI is running, please wait...", vim.log.levels.WARN)
                return
            end
            local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local new_content = table.concat(buf_lines, "\n")
            context.set_content(new_content)
            vim.api.nvim_buf_set_option(bufnr, "modified", false)
            vim.notify("Context saved", vim.log.levels.INFO)
        end,
    })

    -- ========================================================================
    -- AI Actions
    -- ========================================================================

    local function ai_generate()
        if ai_state.running then
            vim.notify("AI is already running", vim.log.levels.WARN)
            return
        end

        local backend = ai.detect_backend()
        if not backend then
            vim.notify("No AI backend found", vim.log.levels.ERROR)
            return
        end

        local files = get_marked_files_content()
        if #files == 0 then
            vim.notify("No marked files. Mark files first with :Quarker mark", vim.log.levels.WARN)
            return
        end

        -- Ask for seed prompt
        vim.ui.input({ prompt = "Context seed (optional): " }, function(seed)
            local existing = context.get_content()
            local prompt = build_generate_context_prompt(files, seed, existing)

            run_ai_with_loading(bufnr, winid, backend, prompt, "Generating context...", function(result)
                if result and result ~= "" then
                    context.set_content(result)
                    reload_content(bufnr, result)
                    vim.notify("Context generated", vim.log.levels.INFO)
                end
            end)
        end)
    end

    local function ai_refresh()
        if ai_state.running then
            vim.notify("AI is already running", vim.log.levels.WARN)
            return
        end

        local backend = ai.detect_backend()
        if not backend then
            vim.notify("No AI backend found", vim.log.levels.ERROR)
            return
        end

        local existing = context.get_content()
        if existing == "" then
            vim.notify("No existing context. Generate first with 'g'", vim.log.levels.WARN)
            return
        end

        vim.ui.input({ prompt = "Diff since (default HEAD~1): ", default = "HEAD~1" }, function(since)
            since = since or "HEAD~1"

            local diff_result = vim.fn.systemlist("git diff " .. since .. " 2>/dev/null")
            if vim.v.shell_error ~= 0 or #diff_result == 0 then
                vim.notify("No diff found for " .. since, vim.log.levels.WARN)
                return
            end

            local diff = table.concat(diff_result, "\n")
            local prompt = build_refresh_context_prompt(diff, existing)

            run_ai_with_loading(bufnr, winid, backend, prompt, "Refreshing from diff...", function(result)
                if result and result ~= "" then
                    context.set_content(result)
                    reload_content(bufnr, result)
                    vim.notify("Context refreshed", vim.log.levels.INFO)
                end
            end)
        end)
    end

    local function ai_feature()
        if ai_state.running then
            vim.notify("AI is already running", vim.log.levels.WARN)
            return
        end

        local backend = ai.detect_backend()
        if not backend then
            vim.notify("No AI backend found", vim.log.levels.ERROR)
            return
        end

        vim.ui.input({ prompt = "Feature name: " }, function(name)
            if not name or name == "" then
                return
            end

            local files = get_marked_files_content()
            local prompt = build_feature_note_prompt(name, files)

            run_ai_with_loading(bufnr, winid, backend, prompt, "Documenting feature: " .. name, function(result)
                if result and result ~= "" then
                    -- Create features directory
                    local base_scope = quarker.get_scope()
                    local features_dir = base_scope .. "/features/" .. name
                    vim.fn.mkdir(features_dir, "p")

                    -- Write note.md
                    local note_path = features_dir .. "/note.md"
                    local f = io.open(note_path, "w")
                    if f then
                        f:write(result)
                        f:close()
                        vim.notify("Feature note: " .. note_path, vim.log.levels.INFO)

                        -- Reload original context
                        reload_content(bufnr, context.get_content())
                    end
                end
            end)
        end)
    end

    local function export_context()
        context.export()
    end

    -- Close with q or Esc
    local function close_window()
        if ai_state.running then
            vim.notify("AI is running, please wait...", vim.log.levels.WARN)
            return
        end

        -- Check if modified
        if vim.api.nvim_buf_get_option(bufnr, "modified") then
            local choice = vim.fn.confirm("Save changes?", "&Yes\n&No\n&Cancel", 1)
            if choice == 1 then
                vim.cmd("write")
            elseif choice == 3 then
                return
            end
        end
        float.close_float_win(winid)
    end

    -- Keymaps
    float.set_float_keymaps(bufnr, {
        { mode = "n", key = "q", callback = close_window, desc = "Close" },
        { mode = "n", key = "<Esc>", callback = close_window, desc = "Close" },
        { mode = "n", key = "<leader>g", callback = ai_generate, desc = "AI Generate" },
        { mode = "n", key = "<leader>r", callback = ai_refresh, desc = "AI Refresh" },
        { mode = "n", key = "<leader>f", callback = ai_feature, desc = "AI Feature Note" },
        { mode = "n", key = "x", callback = export_context, desc = "Export" },
    })
end

return M
