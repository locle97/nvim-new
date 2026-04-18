local M = {}

-- ============================================================================
-- AI Backend Detection
-- ============================================================================

local function executable_exists(cmd)
    return vim.fn.executable(cmd) == 1
end

-- Detect available AI backend (priority: claude > cursor-agent > copilot)
function M.detect_backend()
    if executable_exists("claude") then
        return "claude"
    elseif executable_exists("cursor-agent") then
        return "cursor-agent"
    elseif executable_exists("copilot") then
        return "copilot"
    end
    return nil
end

-- ============================================================================
-- Context Gathering
-- ============================================================================

-- Get marked files content
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

-- Get current context content
local function get_current_context()
    local context = require("quarker.context")
    return context.get_content()
end

-- Get git diff
local function get_git_diff(since)
    since = since or "HEAD~1"
    local result = vim.fn.systemlist("git diff " .. since .. " 2>/dev/null")
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return table.concat(result, "\n")
end

-- Get staged (cached) git diff
local function get_staged_diff()
    local result = vim.fn.systemlist("git diff --cached 2>/dev/null")
    if vim.v.shell_error ~= 0 then
        return nil
    end
    local diff = table.concat(result, "\n")
    if diff == "" then
        return nil
    end
    return diff
end

-- Search for patterns in codebase
local function search_codebase(patterns)
    local results = {}
    for _, pattern in ipairs(patterns) do
        local cmd = string.format("rg -l '%s' --type lua --type ts --type js 2>/dev/null | head -10", pattern)
        local files = vim.fn.systemlist(cmd)
        if vim.v.shell_error == 0 then
            for _, f in ipairs(files) do
                results[f] = true
            end
        end
    end

    local file_list = {}
    for f, _ in pairs(results) do
        table.insert(file_list, f)
    end
    return file_list
end

-- ============================================================================
-- Prompt Builders
-- ============================================================================

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
]]

    return prompt
end

local function build_feature_note_prompt(name, files, search_results)
    local prompt = string.format([[You are documenting a feature called "%s".

## Instructions
Generate a feature note document for AI-assisted development.

## Relevant Files
]], name)

    for _, file in ipairs(files) do
        prompt = prompt .. string.format("\n### %s\n```\n%s\n```\n", file.path, file.content)
    end

    if #search_results > 0 then
        prompt = prompt .. "\n## Additional files found by search\n"
        for _, f in ipairs(search_results) do
            prompt = prompt .. "- " .. f .. "\n"
        end
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
]]

    return prompt
end

local function build_commit_msg_prompt(diff)
    return [[You are an expert developer writing git commit messages.
Analyze the following staged diff and write a concise, informative commit message following conventional commits format.

Rules:
- First line: type(scope): short description (max 72 chars)
- type: feat, fix, refactor, style, docs, test, chore, perf
- Optional blank line + body with more details if needed
- Be specific about WHAT changed and WHY (not just "update files")
- No period at end of subject line

## Staged Diff
```diff
]] .. diff .. [[
```

Output ONLY the commit message text, no explanation or markdown code fences.
]]
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
Return the complete updated context document.
]]

    return prompt
end

-- ============================================================================
-- AI Execution
-- ============================================================================

local function run_ai_command(backend, prompt, callback)
    local cmd
    local args = {}

    if backend == "claude" then
        -- Claude CLI: echo prompt | claude --print
        cmd = "claude"
        args = { "--print", "--model", "haiku" }
    elseif backend == "cursor-agent" then
        -- cursor-agent (assuming similar interface)
        cmd = "cursor-agent"
        args = { "--print" }
    elseif backend == "copilot" then
        -- copilot CLI
        cmd = "copilot"
        args = { "chat", "--no-interactive" }
    else
        vim.notify("No AI backend available", vim.log.levels.ERROR)
        return
    end

    -- Write prompt to temp file
    local tmpfile = vim.fn.tempname()
    local f = io.open(tmpfile, "w")
    if not f then
        vim.notify("Failed to create temp file", vim.log.levels.ERROR)
        return
    end
    f:write(prompt)
    f:close()

    -- Build command
    local full_cmd
    if backend == "claude" then
        full_cmd = string.format("cat '%s' | claude --print 2>&1", tmpfile)
    elseif backend == "cursor-agent" then
        full_cmd = string.format("cat '%s' | cursor-agent 2>&1", tmpfile)
    else
        full_cmd = string.format("cat '%s' | %s %s 2>&1", tmpfile, cmd, table.concat(args, " "))
    end

    vim.notify("Running AI command with " .. backend .. "...", vim.log.levels.INFO)

    -- Run async
    vim.fn.jobstart(full_cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            os.remove(tmpfile)
            if data then
                local result = table.concat(data, "\n")
                -- Trim leading/trailing whitespace
                result = result:gsub("^%s+", ""):gsub("%s+$", "")
                if callback then
                    callback(result)
                end
            end
        end,
        on_stderr = function(_, data)
            if data and #data > 0 and data[1] ~= "" then
                vim.notify("AI stderr: " .. table.concat(data, "\n"), vim.log.levels.WARN)
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 then
                vim.notify("AI command failed with code " .. code, vim.log.levels.ERROR)
                os.remove(tmpfile)
            end
        end,
    })
end

-- ============================================================================
-- Public Commands
-- ============================================================================

-- Generate base context from marked files
function M.generate_context(seed_prompt)
    local backend = M.detect_backend()
    if not backend then
        vim.notify("No AI backend found (tried: claude, cursor-agent, copilot)", vim.log.levels.ERROR)
        return
    end

    local files = get_marked_files_content()
    if #files == 0 then
        vim.notify("No marked files. Mark some files first with :Quarker mark", vim.log.levels.WARN)
        return
    end

    local existing = get_current_context()
    local prompt = build_generate_context_prompt(files, seed_prompt, existing)

    run_ai_command(backend, prompt, function(result)
        if result and result ~= "" then
            local context = require("quarker.context")
            context.set_content(result)
            vim.notify("Context generated and saved", vim.log.levels.INFO)

            -- Open context UI to show result
            vim.schedule(function()
                require("quarker.ui").show_context()
            end)
        end
    end)
end

-- Generate feature note
function M.generate_feature_note(name)
    if not name or name == "" then
        vim.notify("Feature name required", vim.log.levels.ERROR)
        return
    end

    local backend = M.detect_backend()
    if not backend then
        vim.notify("No AI backend found (tried: claude, cursor-agent, copilot)", vim.log.levels.ERROR)
        return
    end

    local files = get_marked_files_content()

    -- Search for related files
    local search_results = search_codebase({ name, "rule", "render", "template" })

    local prompt = build_feature_note_prompt(name, files, search_results)

    run_ai_command(backend, prompt, function(result)
        if result and result ~= "" then
            -- Create features directory
            local quarker = require("quarker")
            local base_scope = quarker.get_scope()
            local features_dir = base_scope .. "/features/" .. name
            vim.fn.mkdir(features_dir, "p")

            -- Write note.md
            local note_path = features_dir .. "/note.md"
            local f = io.open(note_path, "w")
            if f then
                f:write(result)
                f:close()
                vim.notify("Feature note saved: " .. note_path, vim.log.levels.INFO)

                -- Open the file
                vim.schedule(function()
                    vim.cmd("edit " .. vim.fn.fnameescape(note_path))
                end)
            else
                vim.notify("Failed to write feature note", vim.log.levels.ERROR)
            end
        end
    end)
end

-- Refresh context from git diff
function M.refresh_context(since)
    since = since or "HEAD~1"

    local backend = M.detect_backend()
    if not backend then
        vim.notify("No AI backend found (tried: claude, cursor-agent, copilot)", vim.log.levels.ERROR)
        return
    end

    local diff = get_git_diff(since)
    if not diff or diff == "" then
        vim.notify("No diff found for " .. since, vim.log.levels.WARN)
        return
    end

    local existing = get_current_context()
    if existing == "" then
        vim.notify("No existing context. Use :Quarker ai generate first", vim.log.levels.WARN)
        return
    end

    local prompt = build_refresh_context_prompt(diff, existing)

    run_ai_command(backend, prompt, function(result)
        if result and result ~= "" then
            local context = require("quarker.context")
            context.set_content(result)
            vim.notify("Context refreshed from diff", vim.log.levels.INFO)

            -- Open context UI to show result
            vim.schedule(function()
                require("quarker.ui").show_context()
            end)
        end
    end)
end

-- Open a floating window for the commit message (loading or result)
local function show_commit_float(initial_lines)
    local float = require("quarker.ui.float")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "gitcommit")

    local win_config = float.get_window_config(
        0.6, 0.35,
        " Commit Message ",
        "[y] yank  [<CR>] commit --no-verify  [e] edit  [q] close"
    )
    local winid = vim.api.nvim_open_win(bufnr, true, win_config)
    vim.api.nvim_win_set_option(winid, "wrap", true)
    vim.api.nvim_win_set_option(winid, "cursorline", true)

    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

    local function close()
        if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_close(winid, true)
        end
    end

    local function get_msg()
        if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        return table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function yank_msg()
        local msg = get_msg()
        if not msg then return end
        vim.fn.setreg("+", msg)
        vim.fn.setreg('"', msg)
        vim.notify("Commit message yanked to clipboard", vim.log.levels.INFO)
        close()
    end

    local function do_commit()
        local msg = get_msg()
        if not msg or msg == "" then return end
        close()
        -- Write message to a temp file to safely handle multi-line messages
        local tmpfile = vim.fn.tempname()
        local f = io.open(tmpfile, "w")
        if not f then
            vim.notify("Failed to create temp file for commit", vim.log.levels.ERROR)
            return
        end
        f:write(msg)
        f:close()
        vim.fn.jobstart({ "git", "commit", "--no-verify", "-F", tmpfile }, {
            on_exit = function(_, code)
                os.remove(tmpfile)
                vim.schedule(function()
                    if code == 0 then
                        vim.notify("Committed successfully (--no-verify)", vim.log.levels.INFO)
                    else
                        vim.notify("git commit failed (exit " .. code .. ")", vim.log.levels.ERROR)
                    end
                end)
            end,
        })
    end

    float.set_float_keymaps(bufnr, {
        { key = "q",     callback = close,      desc = "Close" },
        { key = "<Esc>", callback = close,      desc = "Close" },
        { key = "y",     callback = yank_msg,   desc = "Yank commit message" },
        { key = "<CR>",  callback = do_commit,  desc = "git commit --no-verify" },
        { key = "e",     callback = function()
            vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
            vim.notify("Buffer is now editable", vim.log.levels.INFO)
        end, desc = "Edit message" },
    })

    return bufnr, winid
end

-- Generate a commit message from staged changes using LLM (async)
function M.generate_commit_msg()
    local backend = M.detect_backend()
    if not backend then
        vim.notify("No AI backend found (tried: claude, cursor-agent, copilot)", vim.log.levels.ERROR)
        return
    end

    local diff = get_staged_diff()
    if not diff then
        vim.notify("No staged changes. Use `git add` to stage hunks first.", vim.log.levels.WARN)
        return
    end

    -- Open the window immediately so the user can keep working
    local bufnr, winid = show_commit_float({
        "  Analyzing staged changes with " .. backend .. "...",
        "",
        "  (Working in background — you can switch windows)",
    })

    local prompt = build_commit_msg_prompt(diff)

    run_ai_command(backend, prompt, function(result)
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then
                -- Window was closed before result arrived; notify instead
                if result and result ~= "" then
                    vim.notify("Commit msg ready (window closed). Yanked to clipboard.", vim.log.levels.INFO)
                    vim.fn.setreg("+", result)
                    vim.fn.setreg('"', result)
                end
                return
            end

            local lines
            if result and result ~= "" then
                lines = vim.split(result, "\n")
            else
                lines = { "  No result returned from AI backend." }
            end

            vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

            -- Bring the window back into focus
            if vim.api.nvim_win_is_valid(winid) then
                vim.api.nvim_set_current_win(winid)
            end
        end)
    end)
end

-- Show detected backend
function M.status()
    local backend = M.detect_backend()
    if backend then
        vim.notify("AI backend: " .. backend, vim.log.levels.INFO)
    else
        vim.notify("No AI backend found (tried: claude, cursor-agent, copilot)", vim.log.levels.WARN)
    end
end

return M
