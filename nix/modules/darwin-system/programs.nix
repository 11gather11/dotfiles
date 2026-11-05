{
  programs = {
    # 1Password CLI (GUI is managed via Homebrew cask - requires /Applications)
    _1password.enable = true;

    # nix-index for command-not-found; comma is nix/modules/home/comma.nix
    nix-index.enable = true;
  };

}
