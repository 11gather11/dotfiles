{
  config,
  helpers,
  ...
}:
let
  # User configuration (shared with jj)
  user = helpers.mkUser config;
in
{
  programs.git = {
    enable = true;

    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHp5tBXsTVMpQWj77wktrQFJeSN0GM4NHfpPNf8Pkw9Z";
      signByDefault = true;
      format = "ssh";
    };

    lfs.enable = true;

    settings = {
      user = {
        name = user.username;
        inherit (user) email;
      };

      core = {
        autocrlf = "input";
        ignorecase = false;
        untrackedCache = false;
        fsmonitor = false;
      };

      ghq = {
        root = [
          "~/ghq"
        ];
      };

      color.ui = "auto";

      tag.sort = "version:refname";

      push = {
        default = "simple";
        autoSetupRemote = true;
        useForceIfIncludes = true;
      };

      commit.verbose = true;

      credential = {
        "https://github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
        "https://gist.github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
      };

      fetch = {
        writeCommitGraph = true;
        prune = true;
        pruneTags = true;
        all = true;
      };

      init.defaultBranch = "main";

      diff = {
        lockb = {
          textconv = "bun";
          binary = true;
        };
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
        renames = true;
      };

      rebase = {
        autoStash = true;
        autoSquash = true;
        updateRefs = true;
      };

      merge = {
        ff = false;
        conflictstyle = "zdiff3";
      };

      pull.rebase = true;

      remote.pushDefault = "origin";

      column.ui = "auto";

      branch.sort = "-committerdate";

      help.autocorrect = "prompt";

      rerere = {
        enabled = true;
        autoupdate = true;
      };
    };

    # Work-specific configuration (manually managed)
    # Create ~/.gitconfig.work for work-related settings
    includes = [
      {
        condition = "gitdir:~/work/";
        path = "~/.gitconfig.work";
      }
    ];

    ignores = [
      # Environment
      ".venv"
      ".direnv"
      ".env"

      #macOS
      ".DS_Store"
      "._*"
      ".Spotlight-V100"
      ".Trashes"

      # Claude Code
      "**/.claude/settings.local.json"
      "**/CLAUDE.local.md"
    ];
  };
}
