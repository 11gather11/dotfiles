{ config, ... }:
{
  programs.git = {
    enable = true;

    # Work-specific configuration (manually managed)
    # Create ~/.gitconfig.work for work-related settings
    includes = [
      { path = "~/.gitconfig.work"; }
    ];

    settings = {
      # Default user settings (personal)
      user = {
        name = "11gather11";
        email = "160300516+11gather11@users.noreply.github.com";
      };

      # ghq root configuration
      ghq = {
        root = "~/ghq";
      };

      # Basic Git settings
      init.defaultBranch = "main";
      pull.rebase = true;
      push.default = "current";
      push.autoSetupRemote = true;

      # diff and merge
      diff.algorithm = "histogram";
      merge.conflictstyle = "zdiff3";

      # credential helper (use 1Password via gh CLI)
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
    };
  };
}
