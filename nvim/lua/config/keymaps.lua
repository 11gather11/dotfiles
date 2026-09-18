-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- With kana input on, Space reaches Neovim as a full-width space, so the leader
-- never fires. That happens after typing Japanese in another pane and coming
-- back without pressing Esc, which is the key Karabiner uses to switch back to
-- eisuu. Rather than guessing when focus returns, this waits for the symptom:
-- a full-width space outside insert mode drops to the ABC layout and then acts
-- as the Space it was meant to be, so the keys typed after it arrive as ASCII.
--
-- Insert mode is left alone, where a full-width space is text.
local ascii_input_source = "com.apple.keylayout.ABC"
vim.keymap.set({ "n", "x", "o" }, "　", function()
  if vim.fn.executable("macism") == 1 then
    vim.system({ "macism", ascii_input_source }):wait()
  end
  vim.api.nvim_feedkeys(vim.keycode("<Space>"), "m", false)
end, { desc = "Leader, after leaving kana input" })
