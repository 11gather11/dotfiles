-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- The typescript extra picks its language server from this, and vtsls is its
-- default. TypeScript 7 is the Go rewrite, so its compiler is also the server
-- and both are named tsc; Nix installs it as part of typescript.
vim.g.lazyvim_ts_lsp = "tsc"

-- LazyVim turns spell checking on for markdown and git commits. Without cjk,
-- every Japanese word in them is underlined as a misspelling.
vim.opt.spelllang = { "en", "cjk" }
