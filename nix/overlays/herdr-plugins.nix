final: prev:
let
  # prev, not final: this attribute set is what the overlay contributes, so
  # resolving through final would require its own output to already exist.
  fetch = prev.fetchFromGitHub;
in
{
  # tmux-style 1-9 numbering. Its tab naming is switched off in the module: every
  # pane here is an agent, so naming a tab after its foreground process would
  # read `claude` on all of them and flip with focus.
  herdr-automatic-rename = fetch {
    owner = "qu8n";
    repo = "herdr-automatic-rename";
    tag = "v0.6.1";
    hash = "sha256-r085XqqTHGg9+k+uC7cTp4M2Er186zM53mwSdrdfyis=";
  };

  # Writes herdr's workspace/tab/agent context out to the terminal's own title —
  # what the window manager and the app switcher show.
  herdr-window-title-sync = fetch {
    owner = "rjyo";
    repo = "herdr-window-title-sync";
    # No tags published; pinned to the commit read when this was written.
    rev = "b07f1140b7308d66487b2f4be546c0c7db065569";
    hash = "sha256-NyRmPI7Ja0NGVzKpMOYWXdK9rISMD5xT27XCW2z6DAw=";
  };
}
