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
      git-wt
      bit
      git-lfs
      ghq
      lazygit
      lazydocker
      # Search & file utilities
      ripgrep
      fd
      fzf
      zoxide
      bat
      eza
      wezterm
      jq
      dust
      delta
      tre
      vivid
      pastel
      hexyl
      # Development languages
      nodejs_24
      bun
      deno

      #LSP
      nixd

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
    ]
    # Platform-specific GUI applications
    # discord only supports x86_64-linux, x86_64-darwin, aarch64-darwin (not aarch64-linux)
    ++ lib.optionals (isDarwin || isX86Linux) [
      discord
    ];
}
