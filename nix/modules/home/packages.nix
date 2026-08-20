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
    git-now
    worktrunk
    git-lfs
    ghq
    lazygit
    serie
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
