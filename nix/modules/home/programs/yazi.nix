# TUI file manager, for the two things the shell here does not cover: renaming
# a batch of files, and moving between two directories that are not ~/Downloads
# (which dlmv handles).
{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;

    # Wraps yazi so the shell follows it out — quit in a directory and the
    # shell is left there. Without this it is a viewer you always cd back from.
    enableFishIntegration = true;

    plugins = {
      inherit (pkgs.yaziPlugins)
        # Which files are changed, without leaving the tree: status letters
        # beside each name, branch and ahead/behind across the top.
        git
        githead
        # One key that opens a file or enters a directory, rather than two.
        smart-enter
        # f<char>, so a long listing does not have to be scrolled.
        jump-to-char
        # Panes read as panes — which matters inside a herdr split, where
        # yazi's own panes sit next to someone else's.
        full-border
        lazygit
        ;
      # Not in nixpkgs; see nix/packages/yazi-eza-preview.
      eza-preview = pkgs.yazi-eza-preview;
    };

    # Installing a plugin only places it. Each of these also has to be turned
    # on — a setup call, a fetcher, or a key — and until that is written here
    # they sit in the plugins directory doing nothing.
    initLua = ''
      require("full-border"):setup()
      require("githead"):setup()
      require("git"):setup()

      -- The tree keeps its own idea of what to show, separate from the file
      -- list's, so hiding dotfiles has to be turned off in both places.
      require("eza-preview"):setup {
        default_tree = true,
        all = true,
        git_status = true,
      }
    '';

    settings = {
      # Dotfiles shown. What is browsed here is repositories, where .github,
      # .claude and .works carry as much as anything without a dot — hiding
      # them makes the listing a wrong picture of the directory. `.` still
      # toggles it per session.
      mgr.show_hidden = true;

      plugin = {
        prepend_previewers = [
          {
            # A directory previewed as a tree rather than one level. What is
            # being looked for here is the shape of a repository, and one level
            # does not show it.
            url = "*/";
            run = "eza-preview";
          }
        ];

        # Both entries are needed: files and directories are fetched separately.
        prepend_fetchers = [
          {
            url = "*";
            run = "git";
            group = "git";
          }
          {
            url = "*/";
            run = "git";
            group = "git";
          }
        ];
      };
    };

    keymap.mgr.prepend_keymap = [
      {
        on = "l";
        run = "plugin smart-enter";
        desc = "Enter the directory, or open the file";
      }
      {
        on = "f";
        run = "plugin jump-to-char";
        desc = "Jump to char";
      }
      {
        on = [
          "g"
          "i"
        ];
        run = "plugin lazygit";
        desc = "Run lazygit here";
      }
      {
        on = [
          "e"
          "t"
        ];
        run = "plugin eza-preview";
        desc = "Toggle tree/list dir preview";
      }
      {
        on = [
          "e"
          "-"
        ];
        run = "plugin eza-preview inc-level";
        desc = "Increment tree level";
      }
      {
        on = [
          "e"
          "_"
        ];
        run = "plugin eza-preview dec-level";
        desc = "Decrement tree level";
      }
      {
        on = [
          "e"
          "*"
        ];
        run = "plugin eza-preview toggle-hidden";
        desc = "Toggle hidden files";
      }
      {
        on = [
          "e"
          "g"
          "s"
        ];
        run = "plugin eza-preview toggle-git-status";
        desc = "Toggle git status in the tree";
      }
    ];
  };
}
