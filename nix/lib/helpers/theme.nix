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

  # hunk ships the scheme as one of its built-in themes, under an id.
  hunk = "catppuccin-mocha";

  # The colours delta paints an added and a removed line with, taken from
  # catppuccin/delta rather than left at delta's own — which are a saturated
  # green and red mixed with nothing, and read as a warning next to a scheme
  # this muted. Each background here is the accent colour at 20% over the
  # scheme's base, 35% for the emphasised span inside a changed line.
  #
  # Written as delta style strings: an optional foreground word (`syntax` keeps
  # the syntax highlighting), then the background, then attributes.
  #
  # The gitconfig reads this; a second reader existed while a file manager
  # rendered diffs in its preview, and passed the same values as arguments
  # because it ran delta with --no-gitconfig.
  delta = {
    minus-style = "syntax \"#493447\"";
    minus-emph-style = "bold syntax \"#694559\"";
    plus-style = "syntax \"#394545\"";
    plus-emph-style = "bold syntax \"#4e6356\"";
    line-numbers-minus-style = "bold \"#f38ba8\"";
    line-numbers-plus-style = "bold \"#a6e3a1\"";
    line-numbers-left-style = "\"#6c7086\"";
    line-numbers-right-style = "\"#6c7086\"";
    line-numbers-zero-style = "\"#6c7086\"";
  };
}
