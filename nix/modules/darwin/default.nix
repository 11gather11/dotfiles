{
  imports = [
    # macOS-specific packages
    ./packages.nix

    # macOS-specific dotfiles
    ./dotfiles.nix

    # Docker configuration (OrbStack)
    ./programs/docker.nix
  ];
}
