---@module 'lazy'

-- Dotfiles are shown everywhere the picker looks. What is browsed here is
-- repositories, where .github, .claude and .envrc carry as much as anything
-- without a dot — and the alternative is pressing alt+h on arrival, every
-- time. LazyVim's own author sets this in the same three places.
return {
  {
    "snacks.nvim",
    init = function()
      -- snacks hides an image viewer's placement when its buffer leaves every
      -- window and never unhides it, so returning to the buffer shows a blank.
      -- Unmerged upstream: https://github.com/folke/snacks.nvim/pull/2793
      -- Patched on state(), which each update looks up afresh, so it also
      -- reaches placements created before this runs.
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          local Placement = require("snacks.image.placement")
          local state = Placement.state
          function Placement:state()
            -- auto_resize marks the image viewer; inline placements in
            -- documents show and hide themselves.
            if self.hidden and self.opts.auto_resize and #self:wins() > 0 then
              self.hidden = false
            end
            return state(self)
          end
        end,
      })
    end,
    ---@type snacks.Config
    opts = {
      -- Opening an image file shows the image, and images referenced from
      -- markdown render in place. Everything but PNG goes through ImageMagick,
      -- which the neovim module puts on PATH.
      image = {},
      picker = {
        sources = {
          explorer = {
            hidden = true,
            -- Git-ignored entries too: .claude, .env and CLAUDE.local.md are
            -- ignored by design and are among the files opened most here.
            ignored = true,
            layout = { layout = { position = "right" } },
          },
          files = { hidden = true },
          grep = { hidden = true },
        },
      },
    },
  },
}
