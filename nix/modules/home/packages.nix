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
    # Reading a changeset an agent wrote, which is most of them now. Took
    # reviewr's place: same job, without a herdr plugin and a pinned binary.
    hunk
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
    bun
    pnpm
    uv
    # Misc utilities
    fixjson
    #LSP
    nixd
  ];
}
