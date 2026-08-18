{
  programs = {
    # 1Password CLI (GUI is managed via Homebrew cask - requires /Applications)
    _1password.enable = true;

    # nix-index for command-not-found and comma
    nix-index.enable = true;
    nix-index-database.comma.enable = true;
  };

}
