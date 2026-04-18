local M = {}

-- Configuration with defaults
local config = {
    mark_icon = "⭐",
    mark_hl_group = "String",
    score_offset = 10000,
    enabled = true,
}

-- Setup function for user configuration
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Build mark lookup table for O(1) access
-- Returns lookup table and mark count
local function build_mark_lookup()
    local quarker = require('quarker')
    local marks = quarker.get_marks()
    local lookup = {}
    local mark_count = #marks

    for i, mark in ipairs(marks) do
        -- Store both relative and absolute paths for lookup
        -- to handle different path formats from Telescope
        lookup[mark.path] = i          -- relative path
        lookup[mark.full_path] = i     -- absolute path
    end

    return lookup, mark_count
end

-- Create custom sorter that prioritizes marked files
function M.create_quarker_sorter(opts)
    opts = opts or {}
    local conf = require('telescope.config').values
    local base_sorter = conf.file_sorter(opts)

    -- Cache marks once when sorter is created
    local mark_lookup, mark_count = build_mark_lookup()

    -- Wrap the scoring function
    local original_scoring = base_sorter.scoring_function

    base_sorter.scoring_function = function(self, prompt, line, entry)
        -- Get the original fuzzy match score first
        local original_score = original_scoring(self, prompt, line, entry)

        -- Check if file is marked
        local mark_index = mark_lookup[line]

        if mark_index then
            -- For marked files:
            -- 1. If prompt is empty, show all marked files at top
            -- 2. If prompt exists, telescope's original scorer already filtered it
            --    If original_score is reasonable (file matches), boost it to top
            --    If original_score is very high (file doesn't match), keep it high

            if prompt == "" or prompt == nil then
                -- No search - show all marked files at top
                return -(config.score_offset + (mark_count - mark_index))
            else
                -- With search - only boost marked files that actually match
                -- If score is very high, it means telescope filtered it out
                -- Let's respect that and keep the high score
                if original_score >= 0 and original_score < 1000 then
                    -- File matches the search - boost it to top
                    return -(config.score_offset + (mark_count - mark_index))
                else
                    -- File doesn't match - let telescope filter it naturally
                    return original_score
                end
            end
        end

        -- Use original scoring for unmarked files
        return original_score
    end

    return base_sorter
end

-- Create custom entry maker that adds visual indicators to marked files
function M.create_quarker_entry_maker(opts)
    opts = opts or {}
    local make_entry = require('telescope.make_entry')
    local base_entry_maker = make_entry.gen_from_file(opts)

    -- Cache marks once when entry maker is created
    local mark_lookup = build_mark_lookup()

    return function(line)
        local entry = base_entry_maker(line)
        if not entry then return nil end

        -- Check if marked (check both the line and the entry path)
        local mark_index = mark_lookup[line] or mark_lookup[entry.path]
        entry.is_marked = mark_index ~= nil
        entry.mark_index = mark_index

        -- Wrap display function to add icon and index
        local original_display = entry.display
        entry.display = function(e)
            local display_str, highlights = original_display(e)

            if e.is_marked and e.mark_index then
                -- Prepend index number and icon
                local prefix = string.format("%d. %s ", e.mark_index, config.mark_icon)
                display_str = prefix .. display_str

                -- Adjust highlight positions for prefix offset
                if highlights then
                    local prefix_len = #prefix
                    for _, hl in ipairs(highlights) do
                        if type(hl[1]) == "table" and #hl[1] >= 2 then
                            hl[1][1] = hl[1][1] + prefix_len  -- start position
                            hl[1][2] = hl[1][2] + prefix_len  -- end position
                        end
                    end
                end
            end

            return display_str, highlights
        end

        return entry
    end
end

-- Enhanced find_files that integrates Quarker marks
function M.find_files(opts)
    opts = opts or {}

    -- Only inject custom components if integration is enabled
    if config.enabled then
        opts.sorter = M.create_quarker_sorter(opts)
        opts.entry_maker = M.create_quarker_entry_maker(opts)
    end

    -- Call original find_files
    require('telescope.builtin').find_files(opts)
end

return M
