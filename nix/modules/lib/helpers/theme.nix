# The colour scheme, named once per tool.
#
# Every tool spells the same theme differently — Ghostty wants a display name,
# bat a sublime theme name, vivid a filename stem — so a single string cannot be
# shared. Keeping the spellings together instead means a theme change is one
# edit here, and a tool that drifted out of the scheme is visible by reading one
# file rather than grepping six.
#
# Each name below is one the tool already ships; none require a downloaded
# theme file. Verify a new scheme is present before switching:
#
#   ghostty +list-themes | rg -i <name>
#   bat --list-themes    | rg -i <name>
#   vivid themes         | rg -i <name>
#   fish -c 'fish_config theme list'
_: {
  # Ghostty's bundled theme, by display name.
  ghostty = "Catppuccin Mocha";

  # bat's sublime-syntax theme. delta reads syntax highlighting through bat, so
  # it takes the same value.
  bat = "Catppuccin Mocha";

  # vivid generates LS_COLORS from this; consumed in fish/config.fish.
  vivid = "catppuccin-mocha";

  # fish/themes/<name>.fish, sourced from fish/config.fish.
  fish = "catppuccin-mocha";

  # The LazyVim colorscheme name, set in nvim/lua/plugins/colorscheme.lua.
  neovim = "catppuccin-mocha";
}
