{
  pkgs,
  lib,
  ...
}:
let
  # Check if we're on a platform that supports certain packages
  inherit (pkgs.stdenv) isDarwin;
  isX86Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
{
  home.packages = 
    with pkgs:
    [
      # Essentials
      curl
      fish
      # VCS
      git
      ghq
      # Search & file utilities

      # Development languages
      nodejs_24
      bun
      # Package managers
      yarn
      pnpm

      # GUI applications (cross-platform)
      vscode
    ]
    # Platform-specific GUI applications
    # discord only supports x86_64-linux, x86_64-darwin, aarch64-darwin (not aarch64-linux)
    ++ lib.optionals (isDarwin || isX86Linux) [
      discord
    ];
};