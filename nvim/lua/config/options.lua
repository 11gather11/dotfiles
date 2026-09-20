-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- The typescript extra picks its language server from this, and vtsls is its
-- default. tsgo is lspconfig's name for the Go rewrite, which Nix installs as
-- part of typescript 7; see nix/modules/home/programs/neovim and plugins/lsp.
vim.g.lazyvim_ts_lsp = "tsgo"

-- LazyVim turns spell checking on for markdown and git commits. Without cjk,
-- every Japanese word in them is underlined as a misspelling.
vim.opt.spelllang = { "en", "cjk" }
