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

  # starship takes no theme name — it wants the colours themselves, declared as
  # a palette its modules then refer to by role.
  starshipPalette = {
    rosewater = "#f5e0dc";
    flamingo = "#f2cdcd";
    pink = "#f5c2e7";
    mauve = "#cba6f7";
    red = "#f38ba8";
    maroon = "#eba0ac";
    peach = "#fab387";
    yellow = "#f9e2af";
    green = "#a6e3a1";
    teal = "#94e2d5";
    sky = "#89dceb";
    sapphire = "#74c7ec";
    blue = "#89b4fa";
    lavender = "#b4befe";
    text = "#cdd6f4";
    subtext0 = "#a6adc8";
    overlay0 = "#6c7086";
    surface0 = "#313244";
    base = "#1e1e2e";
  };
}
