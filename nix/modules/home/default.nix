{
  # pkgs,
  config,
  lib,
  helpers,
  dotfilesDir,
  # system,
  ...
}:
{
  imports = [
    # Common packages
    ./packages.nix

    # Common dotfiles symlinks
    (import ./dotfiles.nix {
      inherit
        config
        lib
        helpers
        dotfilesDir
        ;
    })
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
