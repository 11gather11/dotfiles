{
  pkgs,
  config,
  lib,
  fish-na,
  helpers,
  dotfilesDir,
  ast-grep-skill,
  agent-browser-skill,
  tgrab-skill,
  local-skills,
  # system,
  ...
}:
{
  imports = [
    # Common packages
    ./packages.nix

    # Agent skills for Claude Code (skills from flake inputs)
    (import ./agent-skills.nix {
      inherit
        pkgs
        lib
        ast-grep-skill
        agent-browser-skill
        tgrab-skill
        local-skills
        config
        ;
    })

    # Git hooks for auto-switching nix config on changes
    # Note: pre-commit hook is managed by devShell via git-hooks.nix flakeModule
    (import ./git-hooks.nix {
      inherit
        lib
        dotfilesDir
        ;
    })

    # Program configurations (Claude Code, Codex, Neovim, etc.)
    (import ./programs {
      inherit
        pkgs
        lib
        config
        dotfilesDir
        helpers
        fish-na
        ;
    })

    # Common dotfiles symlinks
    (import ./dotfiles.nix {
      inherit
        config
        lib
        helpers
        dotfilesDir
        ;
    })
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
