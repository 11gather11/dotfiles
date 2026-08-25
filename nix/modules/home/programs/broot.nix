# The explorer for a terminal pane. The tree is the listing, so a file four
# levels down can be selected where it is shown, and typing a few letters
# filters the hierarchy without flattening it.
#
# It replaced yazi, which showed one directory at a time and drew its tree
# into the preview pane as text — something to look at rather than a list to
# act on. The editor's own explorer covers the same ground from inside nvim;
# this is the one that does not need nvim open.
_: {
  programs.broot = {
    enable = true;

    # `br` rather than `broot`: the wrapper writes the last directory out and
    # the shell follows it, so quitting leaves the shell where the browsing
    # ended rather than where it started.
    enableFishIntegration = true;

    settings = {
      # -g git status in the tree, -h dotfiles. What is browsed here is
      # repositories, where both are the point.
      #
      # --cmd runs a command at startup, and the preview panel is wanted from
      # the first frame rather than after a keystroke. Once open it follows the
      # selection, which is the arrangement worth having and the reason this is
      # configured at all.
      default_flags = "-gh --cmd :toggle_preview";

      # Ghostty is already running a Nerd Font for the other tools.
      icon_theme = "nerdfont";

      # broot previews through its own fixed list of syntect themes, and no
      # Catppuccin is among them — GitHub, Solarized, EightiesDark, MochaDark,
      # OceanDark, OceanLight. MochaDark is the nearest dark one and shares
      # nothing with this scheme but the word.
      syntax_theme = "MochaDark";

      # The scheme ships with broot, so there is nothing to fetch, pin or
      # transcribe: the file sits in the package beside the skins the default
      # config offers, and this replaces the dark-blue one it picks.
      #
      # Written as a whole list because it replaces the default `imports`
      # rather than adding to it — verbs.hjson has to be named again or the
      # verb file stops being read.
      imports = [
        "verbs.hjson"
        { file = "skins/catppuccin-mocha.hjson"; }
      ];
    };
  };
}
