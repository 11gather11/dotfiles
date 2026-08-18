{
  imports = [
    # Common packages
    ./packages.nix

    # Agent skills for Claude Code (skills from flake inputs)
    ./agent-skills.nix

    # Git hooks for auto-switching nix config on changes
    # Note: pre-commit hook is managed by devShell via git-hooks.nix flakeModule
    ./git-hooks.nix

    # Program configurations (Claude Code, Codex, Neovim, etc.)
    ./programs

    # Common dotfiles symlinks
    ./dotfiles.nix
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
