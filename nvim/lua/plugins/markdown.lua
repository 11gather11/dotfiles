---@module 'lazy'

-- The markdown extra formats with prettier first, which nothing here installs.
-- This repository formats markdown with oxfmt through treefmt, so formatting on
-- save runs the same formatter the pre-commit hook does. The extra's other two
-- are kept: each only runs when its condition in the extra holds.
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        ["markdown"] = { "oxfmt", "markdownlint-cli2", "markdown-toc" },
        ["markdown.mdx"] = { "oxfmt", "markdownlint-cli2", "markdown-toc" },
      },
    },
  },
}
