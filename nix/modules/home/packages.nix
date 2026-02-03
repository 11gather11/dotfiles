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
    with pkgs;
    [
      # Essentials
      curl
      devenv
      fish
      # VCS
      git
      ghq

      # Containers
      lazydocker

      # Search & file utilities

      # Development languages
      nodejs_24
      bun
      # Go is managed in programs/go.nix
      # Package managers
      yarn
      pnpm

      # Rust tools
      rustc
      cargo
      cargo-make

      # GUI applications (cross-platform)
      vscode

      # Fonts
      plemoljp-nf
    ]
    # Platform-specific GUI applications
    # discord only supports x86_64-linux, x86_64-darwin, aarch64-darwin (not aarch64-linux)
    ++ lib.optionals (isDarwin || isX86Linux) [
      discord
    ];
}
