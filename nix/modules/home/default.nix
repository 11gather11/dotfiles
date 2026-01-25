{
  pkgs,
  config,
  lib,
  dotfilesDir,
  system,
  nodePackages,
  ...
}:
let
  # Import common helpers once
  helpers = import ../lib/helpers { inherit lib; };
in
{
  imports = [
    # Common packages
    ./packages.nix
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}