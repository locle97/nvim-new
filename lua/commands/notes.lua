local notes_dir = "~/notes"

-- Utility to ensure directory exists and expand full path
local function ensure_note_path(path)
  local expanded = vim.fn.expand(path)
  vim.fn.mkdir(vim.fn.fnamemodify(expanded, ":h"), "p")
  return expanded
end

-- Open file with path + content if needed
local function open_note(filepath, template_lines)
  filepath = ensure_note_path(filepath)
  if vim.fn.filereadable(filepath) == 0 and template_lines then
    vim.fn.writefile(template_lines, filepath)
  end
  vim.cmd("edit " .. filepath)
end

-- Today's date
local today = os.date("%Y-%m-%d")

-- Define commands
vim.api.nvim_create_user_command("QuickNote", function()
  local file = notes_dir .. "/quick-notes/" .. today .. "-" .. os.date("%H%M") .. ".md"
  open_note(file, {
    "---",
    "title: Quick Note - " .. today,
    "date: " .. today,
    "tags: [quick]",
    "---",
    "",
    "# Quick Note - " .. today,
    "",
  })
end, {})

vim.api.nvim_create_user_command("DailyNote", function()
  local file = notes_dir .. "/work/meeting/daily/daily-" .. today .. ".md"
  open_note(file, {
    "---",
    "title: Daily Standup - " .. today,
    "date: " .. today,
    "tags: [daily, standup]",
    "---",
    "",
    "# Daily Standup - " .. today,
    "",
    "## What I did yesterday",
    "- ",
    "",
    "## What I'm doing today",
    "- ",
    "",
    "## Blockers / Issues",
    "- ",
    "",
    "## Notes / Discussion",
    "- ",
  })
end, {})

vim.api.nvim_create_user_command("RetroNote", function()
  local file = notes_dir .. "/work/meeting/retro/retro-" .. today .. ".md"
  open_note(file, {
    "---",
    "title: Sprint Retrospective - " .. today,
    "date: " .. today,
    "tags: [sprint, retro]",
    "---",
    "",
    "# Sprint Retrospective - " .. today,
    "",
    "## What went well",
    "- ",
    "",
    "## What didn’t go well",
    "- ",
    "",
    "## What can be improved",
    "- ",
    "",
    "## Action Items",
    "- [ ] ",
    "- [ ] ",
    "",
    "## Health Check",
    "- Team Happiness: 😊 😐 😞",
    "- Process: 👍 👎",
  })
end, {})
