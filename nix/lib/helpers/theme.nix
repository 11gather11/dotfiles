# The colour scheme, for the tools whose Nix modules can be told about it.
#
# Every tool spells the same theme differently — Ghostty wants a display name,
# bat a sublime theme name — so a single string cannot be shared. Keeping the
# spellings together means a theme change is one edit here for these, and a tool
# that drifted out of the scheme is visible by reading one file.
#
# Each name below is one the tool already ships; none require a downloaded theme
# file. Verify a new scheme is present before switching:
#
#   ghostty +list-themes | rg -i <name>
#   bat --list-themes    | rg -i <name>
#
# Not everything themed here can be listed. These take a file or a plugin rather
# than a name, so the scheme is written into the file itself and this attribute
# set cannot reach them — change them by hand, together with the values below:
#
#   fish      fish/themes/catppuccin-mocha.fish, sourced from fish/config.fish
#   vivid     `vivid generate catppuccin-mocha` in fish/config.fish
#   Neovim    nvim/lua/plugins/colorscheme.lua
#   starship  the catppuccin-powerline preset, in programs/starship.nix
_: {
  # Ghostty's bundled theme, by display name.
  ghostty = "Catppuccin Mocha";

  # bat's sublime-syntax theme. delta reads syntax highlighting through bat, so
  # it takes the same value.
  bat = "Catppuccin Mocha";
}
