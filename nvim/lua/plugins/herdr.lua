-- The editor half of the herdr-nvim plugin. The herdr half is a Nix package
-- (nix/packages/herdr-nvim) that runs the sidebar pane; this one puts the
-- annotations in the buffer: comment a line, list the comments, hand them to
-- the agent in the pane next door.
--
-- Default keymaps sit under <leader>a, which neither LazyVim nor anything here
-- claims, so they stay as upstream ships them:
--   <leader>ac comment   <leader>al list   <leader>as send   <leader>aS submit
return {
  { "ChmaraX/herdr-nvim", opts = {} },
}
