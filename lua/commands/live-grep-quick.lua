-- lua/user/live_grep_cmd.lua (or anywhere in your config)
local ok, builtin = pcall(require, "telescope.builtin")
if not ok then
  return
end

vim.api.nvim_create_user_command("LiveGrepQuick", function()
  -- Defer a bit to let UI & buffers settle
  vim.schedule(function()
    builtin.live_grep()
  end)
end, {})
