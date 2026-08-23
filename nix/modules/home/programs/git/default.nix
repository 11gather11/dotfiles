{
  config,
  helpers,
  ...
}:
let
  # User configuration
  user = helpers.mkUser config;

  # Delta settings (shared with lazygit pager configuration)
  deltaSettings = helpers.theme.delta // {
    dark = true;
    syntax-theme = helpers.theme.bat;
    diff-so-fancy = true;
    keep-plus-minus-markers = true;
    side-by-side = true;
    hunk-header-style = "omit";
    line-numbers = true;
  };

  # Aliases file path (copied to Nix store to preserve original formatting)
  # Nix's toGitINI quotes all values, which breaks some tools like 'bit'
  aliasesFile = ./aliases;
in
{
  # Delta pager configuration (used by git)
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = deltaSettings;
  };

  programs.git = {
    enable = true;

    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHp5tBXsTVMpQWj77wktrQFJeSN0GM4NHfpPNf8Pkw9Z";
      signByDefault = true;
      format = "ssh";
    };

    # macOS's own ssh-keygen, not the one in nixpkgs. The key lives in
    # 1Password's agent, and after openssh went to 10.5 the Nix build stopped
    # being able to talk to it — "communication with agent failed" on every
    # commit, while /usr/bin/ssh-keygen signed the same data with the same key.
    # home-manager otherwise points this at the openssh it installs.
    settings.gpg.ssh.program = "/usr/bin/ssh-keygen";

    lfs.enable = true;

    settings = {
      user = {
        name = user.username;
        inherit (user) email;
      };

      core = {
        autocrlf = "input";
        editor = "nvim";
        ignorecase = false;
        untrackedCache = false;
        fsmonitor = false;
      };

      # Personal checkouts. Work lives under ~/ghq-work, reached through the
      # ghq-work function, because ghq has no per-URL root — GHQ_ROOT and this
      # setting are the only controls it offers, and get writes to the last root
      # listed here, so naming both would send everything to one of them.
      #
      # ~/.go/src used to be listed first. It does not exist on this machine and
      # only made `ghq list` walk a second tree for nothing.
      ghq.root = [ "~/ghq" ];

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
          "!/usr/bin/env GH_TOKEN=$(gh auth token --user ${user.username}) gh auth git-credential"
        ];
        "https://gist.github.com".helper = [
          ""
          "!/usr/bin/env GH_TOKEN=$(gh auth token --user ${user.username}) gh auth git-credential"
        ];
      };

      fetch = {
        writeCommitGraph = true;
        prune = true;
        all = true;
      };

      # Prune tags only against origin; a global fetch.pruneTags deletes local
      # tags that are missing from any other fetched remote (e.g. PR fork
      # remotes, which lack release tags)
      remote.origin.pruneTags = true;

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

    # ~/.gitconfig.work holds the work identity, credential helper and signing
    # key. It is deliberately untracked, so only the condition that selects it
    # is configured here.
    #
    # Selected by location, which is the invariant this setup is built on: a
    # checkout under the work root is work, whatever organisation owns it and
    # whatever URL form its remote uses. Nothing is enumerated, so a new client
    # organisation needs no edit here.
    #
    # Remote-based conditions were tried and reverted. `hasconfig:remote.*.url`
    # matches the raw stored URL, and the two work checkouts store different
    # forms — `git@github-work:…` and `ssh://git@github.com/…` — so every host
    # and every URL spelling has to be listed, and the organisation with them.
    # one of them silently took the personal identity under that scheme. The
    # location condition had never been the broken part: it kept resolving
    # correctly for six months while the work root was being written to the
    # wrong place.
    #
    # ~/ghq-work is the work root, sitting next to ~/ghq and named for what it
    # holds rather than nested two levels down as ~/work/ghq was.
    includes = [
      {
        condition = "gitdir:~/ghq-work/";
        path = "~/.gitconfig.work";
      }
      { path = "${aliasesFile}"; }
    ];

    ignores = [
      # Environment
      ".venv"
      ".direnv"

      # macOS
      ".DS_Store"
      ".AppleDouble"
      ".LSOverride"
      "Icon"
      "._*"
      ".DocumentRevisions-V100"
      ".fseventsd"
      ".Spotlight-V100"
      ".TemporaryItems"
      ".Trashes"
      ".VolumeIcon.icns"
      ".com.apple.timemachine.donotpresent"
      ".AppleDB"
      ".AppleDesktop"
      "Network Trash Folder"
      "Temporary Items"
      ".apdisk"

      # Python
      "__pycache__/"
      "*.py[cod]"
      "*$py.class"
      "*.so"
      ".Python"
      "build/"
      "develop-eggs/"
      "dist/"
      "downloads/"
      "eggs/"
      ".eggs/"
      "lib64/"
      "parts/"
      "sdist/"
      "var/"
      "wheels/"
      "pip-wheel-metadata/"
      "share/python-wheels/"
      "*.egg-info/"
      ".installed.cfg"
      "*.egg"
      "MANIFEST"
      "*.manifest"
      "*.spec"
      "pip-log.txt"
      "pip-delete-this-directory.txt"
      "htmlcov/"
      ".tox/"
      ".nox/"
      ".coverage"
      ".coverage.*"
      ".cache"
      "nosetests.xml"
      "coverage.xml"
      "*.cover"
      "*.py,cover"
      ".hypothesis/"
      ".pytest_cache/"
      "*.mo"
      "*.pot"
      "*.log"
      "local_settings.py"
      "db.sqlite3"
      "db.sqlite3-journal"
      "instance/"
      ".webassets-cache"
      ".scrapy"
      "docs/_build/"
      "target/"
      ".ipynb_checkpoints"
      "profile_default/"
      "ipython_config.py"
      ".python-version"
      "__pypackages__/"
      "celerybeat-schedule"
      "celerybeat.pid"
      "*.sage.py"
      ".env"
      "env/"
      "venv/"
      "ENV/"
      "env.bak/"
      "venv.bak/"
      ".spyderproject"
      ".spyproject"
      ".ropeproject"
      "/site"
      ".mypy_cache/"
      ".dmypy.json"
      "dmypy.json"
      ".pyre/"

      # Claude Code
      "**/.claude/settings.local.json"
      "**/.claude/worktrees"
      "**/CLAUDE.local.md"
    ];
  };
}
