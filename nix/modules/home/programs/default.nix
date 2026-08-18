{
  imports = [
    # AI tools
    ./ai-tools.nix

    # Fish shell plugin configuration
    ./fish

    # Claude Code configuration
    ./claude-code

    # Codex configuration
    ./codex.nix

    # GitHub CLI configuration
    ./gh.nix

    # gh-nix: run commands with GitHub token bridged into Nix access-tokens
    ./gh-nix.nix

    # Git configuration
    ./git

    # Neovim configuration
    ./neovim

    # Bat configuration
    ./bat.nix

    # Starship prompt
    ./starship.nix

    # nh: Nix helper CLI with automatic periodic cleanup
    ./nh.nix

    # herdr: agent multiplexer that runs inside the existing terminal
    ./herdr

    # Ghostty terminal configuration
    ./ghostty.nix

    # Direnv configuration with nix-direnv
    ./direnv.nix

    # Lazygit configuration
    ./lazygit
  ];
}
