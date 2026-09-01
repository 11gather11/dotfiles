{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    # Essentials
    curl
    htop
    fish
    # VCS
    git
    worktrunk
    git-lfs
    ghq
    lazygit
    # Security
    tirith
    # Search & file utilities
    ripgrep
    # Structural search, which rg cannot do. The skill for it was installed
    # without this, so the rule that says to prefer it over grep pointed at a
    # command that was not there.
    ast-grep
    fd
    fzf
    zoxide
    bat
    eza
    jq
    dust
    delta
    vivid
    trash-cli
    # Development languages & package managers
    devenv
    nodejs_24
    # Upstream's own build, not nixpkgs'. See nix/flake/shared.nix for why the
    # newer bun is added under its own name instead of replacing nixpkgs'.
    bun-upstream
    pnpm
    uv
    # Misc utilities
    fixjson
    #LSP
    nixd
  ];
}
