return {
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    build = ":KanagawaCompile",
    opts = {
      transparent = true,
      globalStatus = true,
      compile = true,
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "kanagawa-dragon",
    },
  },
}
