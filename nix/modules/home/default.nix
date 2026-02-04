{
  pkgs,
  config,
  lib,
  fish-na,
  helpers,
  dotfilesDir,
  # system,
  ...
}:
{
  imports = [
    # Common packages
    ./packages.nix

    # Program configurations (Claude Code, Codex, Neovim, etc.)
    (import ./programs {
      inherit
        pkgs
        lib
        config
        dotfilesDir
        helpers
        fish-na
        ;
    })

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
