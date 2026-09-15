return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = true,
      -- transparent_background leaves floating windows painted, and the snacks
      -- explorer and pickers are floats, so they showed as solid panels over
      -- Ghostty's translucent background.
      float = { transparent = true },
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
}
