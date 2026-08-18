{ username, ... }:
{
  system = {
    # The nix-darwin state version, not the macOS one. Pinned at first install
    # and left alone: raising it opts into migrations, so it is changed
    # deliberately after reading the release notes, never to "keep current".
    stateVersion = 5;

    # Which user nix-darwin acts as for the things macOS scopes per-user —
    # Homebrew, the user defaults in defaults.nix, and the user launchd agents.
    primaryUser = username;
  };
}
