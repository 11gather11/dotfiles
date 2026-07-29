{
  pkgs,
  lib,
  config,
  dotfilesDir,
  helpers,
  fish-na,
  ...
}:
{
  imports = [
    # AI tools
    ./ai-tools.nix

    # Fish shell plugin configuration
    (import ./fish {
      inherit
        pkgs
        fish-na
        lib
        config
        ;
    })

    # Claude Code configuration
    (import ./claude-code {
      inherit
        pkgs
        lib
        config
        dotfilesDir
        ;
    })

    # Codex configuration
    (import ./codex.nix {
      inherit
        pkgs
        lib
        config
        dotfilesDir
        ;
    })

    # GitHub CLI configuration
    (import ./gh.nix {
      inherit
        pkgs
        lib
        config
        ;
    })

    # gh-nix: run commands with GitHub token bridged into Nix access-tokens
    ./gh-nix.nix

    # Git configuration
    (import ./git {
      inherit
        pkgs
        lib
        config
        helpers
        ;
    })

    # Neovim configuration
    (import ./neovim {
      inherit
        pkgs
        lib
        config
        dotfilesDir
        helpers
        ;
    })

    # Bat configuration
    ./bat.nix

    # nh: Nix helper CLI with automatic periodic cleanup
    ./nh.nix

    # cmux terminal app for Claude Code
    ./cmux

    # Ghostty terminal configuration (used by cmux)
    (import ./ghostty.nix {
      inherit
        pkgs
        lib
        config
        helpers
        ;
    })

    # Direnv configuration with nix-direnv
    ./direnv.nix

    # jj configuration
    (import ./jj.nix {
      inherit
        pkgs
        lib
        config
        helpers
        ;
    })

    # Lazygit configuration
    (import ./lazygit {
      inherit
        pkgs
        lib
        ;
    })
  ];
}
