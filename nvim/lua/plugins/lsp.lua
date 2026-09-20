return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nixd = {},
        -- The nix extra brings nil_ls; nixd already covers the same files.
        nil_ls = { enabled = false },
        lua_ls = {},
        tsc = {
          single_file_support = false,
          workspace_required = true,
        },
      },
    },
  },
}
