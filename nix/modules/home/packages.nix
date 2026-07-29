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
    tmux
    # VCS
    git
    git-now
    git-wt
    git-wtpr
    git-lfs
    ghq
    lazygit
    # Security
    tirith
    # Search & file utilities
    ripgrep
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
    bun
    pnpm
    uv
    # Misc utilities
    fixjson
    #LSP
    nixd
  ];
}
