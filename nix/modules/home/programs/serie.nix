# A rich `git log --graph` that draws the graph through the terminal's image
# protocol rather than box-drawing characters.
#
# Inside a herdr pane this needs `experimental.kitty_graphics` on the herdr
# side — and a herdr server started after that setting was added, since the
# server reads its config once at startup.
{ pkgs, ... }:
let
  tomlFormat = pkgs.formats.toml { };
in
{
  home.packages = [ pkgs.serie ];

  # Single-width cells. The default doubles them, which on a repository with
  # branches running in parallel for weeks pushes the commit list far enough
  # right that branch names are cut off — and a graph whose lines cannot be
  # matched to a name is not telling you much. The names here carry their
  # meaning at the end (…-fix-check-before-update-2), so truncation costs the
  # part that identifies the branch.
  xdg.configFile."serie/config.toml".source = tomlFormat.generate "serie-config.toml" {
    core.option.graph_width = "single";
  };
}
