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

    # Programs
    ./programs

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
