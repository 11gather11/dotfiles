{
  pkgs,
  config,
  lib,
  helpers,
  dotfilesDir,
  ...
}:
{
  imports = [
    # Linux-specific packages
    ./packages.nix

    # Linux-specific dotfiles
    (import ./dotfiles.nix {
      inherit
        pkgs
        config
        lib
        helpers
        dotfilesDir
        ;
    })
  ];

  # nix-index for command-not-found and comma
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;
}
