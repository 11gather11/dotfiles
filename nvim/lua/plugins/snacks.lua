---@module 'lazy'

-- Dotfiles are shown everywhere the picker looks. What is browsed here is
-- repositories, where .github, .claude and .envrc carry as much as anything
-- without a dot — and the alternative is pressing alt+h on arrival, every
-- time. LazyVim's own author sets this in the same three places.
return {
  {
    "snacks.nvim",
    ---@type snacks.Config
    opts = {
      picker = {
        sources = {
          explorer = { hidden = true },
          files = { hidden = true },
          grep = { hidden = true },
        },
      },
    },
  },
}
