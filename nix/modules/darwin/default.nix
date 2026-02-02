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
    # macOS-specific packages
    ./packages.nix

    # macOS-specific dotfiles
    (import ./dotfiles.nix {
      inherit
        pkgs
        config
        lib
        helpers
        dotfilesDir
        ;
    })

    # Docker configuration (OrbStack)
    ./programs/docker.nix
  ];
}
