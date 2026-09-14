---@module 'lazy'

-- Rules markdownlint applies when a repository has no config of its own.
local markdownlint_config = vim.fn.stdpath("config") .. "/markdownlint.jsonc"

return {
  {
    "stevearc/conform.nvim",
    opts = {
      -- The markdown extra formats with prettier first, which nothing here
      -- installs. This repository formats markdown with oxfmt through treefmt,
      -- so formatting on save runs the same formatter the pre-commit hook does.
      -- The extra's other two are kept: each only runs when its condition in
      -- the extra holds.
      formatters_by_ft = {
        ["markdown"] = { "oxfmt", "markdownlint-cli2", "markdown-toc" },
        ["markdown.mdx"] = { "oxfmt", "markdownlint-cli2", "markdown-toc" },
      },
      formatters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", markdownlint_config },
        },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        -- Replaces nvim-lint's args rather than using prepend_args, which
        -- LazyVim appends after them.
        ["markdownlint-cli2"] = {
          args = { "--config", markdownlint_config, "-" },
        },
      },
    },
  },
}
