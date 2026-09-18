---@module 'lazy'

-- Rules markdownlint applies when a repository has no config of its own.
local markdownlint_config = vim.fn.stdpath("config") .. "/markdownlint.jsonc"

-- Each Neovim gets its own port, so two editors can preview at once.
local preview_port = 5500 + vim.uv.os_getpid() % 500

-- The pane the preview browser is shown in, while one is open.
local preview_pane = nil

local function herdr(args)
  return vim.system(vim.list_extend({ "herdr" }, args), { text = true }):wait()
end

-- Toggle a live preview of the markdown being edited. Inside herdr it opens in
-- a terminal-browser pane to the right of this one; elsewhere in the default browser.
local function toggle_preview()
  local lp = require("livepreview")
  local utils = require("livepreview.utils")

  if lp.is_running() then
    lp.close()
    if preview_pane then
      herdr({ "pane", "close", preview_pane })
      preview_pane = nil
    end
    return
  end

  -- The focused window may be the explorer rather than the markdown, so fall
  -- back to a markdown buffer that is open, as live-preview itself does.
  local file = vim.api.nvim_buf_get_name(0)
  if not utils.supported_filetype(file) then
    file = utils.find_supported_buf()
  end
  if not file then
    vim.notify("No markdown buffer to preview", vim.log.levels.WARN)
    return
  end

  local in_herdr = vim.env.HERDR_ENV ~= nil
  -- live-preview runs `<browser> <url>`; `true` makes that a no-op so the pane
  -- below is the only thing opened.
  require("livepreview.config").set({
    port = preview_port,
    dynamic_root = true,
    browser = in_herdr and "true" or "default",
  })
  vim.cmd.LivePreview({ args = { "start", file } })
  if not in_herdr then
    return
  end

  local url = ("http://127.0.0.1:%d/%s"):format(preview_port, vim.uri_encode(vim.fs.basename(file)))

  -- terminal-browser splits the pane it was invoked from, so there is no target
  -- to name: running it from this Neovim is what puts the preview beside it.
  local opened = vim.system({ "terminal-browser", "open", url, "--split", "right" }, { text = true }):wait()
  if opened.code ~= 0 then
    lp.close()
    vim.notify("terminal-browser could not open the preview pane: " .. opened.stderr, vim.log.levels.ERROR)
    return
  end

  -- `open` prints the new browser but not the pane herdr gave it; `ls` has both.
  -- Matching on the key rather than taking the newest entry is what stops two
  -- editors previewing at once from closing each other's pane.
  local key = (vim.json.decode(opened.stdout) or {}).key
  local listed = vim.system({ "terminal-browser", "ls", "--json" }, { text = true }):wait()
  for _, browser in ipairs((vim.json.decode(listed.stdout) or {}).browsers or {}) do
    if browser.key == key then
      preview_pane = browser.pane and browser.pane.pane
    end
  end

  -- terminal-browser has no --no-focus, so the browser takes focus and this
  -- hands it straight back.
  if preview_pane then
    herdr({ "pane", "focus", "--pane", preview_pane, "--direction", "left" })
  end
end

return {
  -- Replaced by live-preview.nvim below, which is still maintained.
  { "iamcco/markdown-preview.nvim", enabled = false },
  {
    "brianhuster/live-preview.nvim",
    cmd = "LivePreview",
    keys = {
      -- Not limited to markdown buffers, so it also works with the explorer
      -- focused.
      { "<leader>cp", toggle_preview, desc = "Markdown Preview" },
    },
    -- live-preview has no theme option, so the theme is spliced into the
    -- page it builds.
    config = function()
      local template = require("livepreview.template")
      local theme = table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/markdown-preview-theme.html"), "\n")
      local md2html = template.md2html
      template.md2html = function(md)
        return (md2html(md):gsub("</head>", function()
          return theme .. "</head>"
        end, 1))
      end
    end,
  },
  -- The editor shows markdown as source; the preview pane is where it is read
  -- rendered. <leader>um still turns rendering on in the editor.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = { enabled = false },
  },
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
