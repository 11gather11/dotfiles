return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nixd = {},
        lua_ls = {},
        tsgo = {
          single_file_support = false,
          workspace_required = true,
        },
      },
    },
  },
}
