{ config, ... }:
{
  programs.git = {
    enable = true;

    # Default user settings (personal)
    userName = "11gather11";
    userEmail = "160300516+11gather11@users.noreply.github.com";

    # Work-specific configuration (manually managed)
    # Create ~/.gitconfig.work for work-related settings
    includes = [
      { path = "~/.gitconfig.work"; }
    ];

    extraConfig = {
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
      credential."https://github.com".helper = "";
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
    };
  };
}
