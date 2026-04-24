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
    bit
    git
    # git-now
    git-wt
    git-lfs
    ghq
    lazygit
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
    deno
    pnpm
    uv
    # Misc utilities
    fixjson
    #LSP
    nixd
  ];
}
