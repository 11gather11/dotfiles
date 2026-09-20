return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nixd = {},
        -- The nix extra brings nil_ls; nixd already covers the same files.
        nil_ls = { enabled = false },
        lua_ls = {},
        tsgo = {
          -- lspconfig still starts this server as `tsgo`, the name npm's
          -- @typescript/native-preview installs it under. Nix installs it as
          -- part of typescript 7, where the same Go binary is named tsc.
          cmd = { "tsc", "--lsp", "--stdio" },
          single_file_support = false,
          workspace_required = true,
        },
      },
    },
  },
}
