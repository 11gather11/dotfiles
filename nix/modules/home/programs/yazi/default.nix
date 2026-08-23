# TUI file manager, for the two things the shell here does not cover: renaming
# a batch of files, and moving between two directories that are not ~/Downloads
# (which dlmv handles).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The plugin written here is linked into place rather than copied into the
  # store, so that editing it takes effect on the next yazi rather than on the
  # next switch — a forty-second build to see whether a number is right is a
  # build nobody runs.
  #
  # It costs reproducibility — the link is dead on a machine without this
  # checkout — so set this false once they settle, and they go back to being
  # copied like every other plugin.
  developing = true;

  localPlugins = {
    gitstat = ./gitstat;
  };

  # The path as it is on this machine, which is what a link out of the store
  # has to name. `./gitstat` would be the store copy this is avoiding.
  checkout = "${config.home.homeDirectory}/ghq/github.com/11gather11/dotfiles/nix/modules/home/programs/yazi";

in
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
        # Narrows the listing to the files git says changed, so a diff can be
        # walked without remembering where the files were.
        vcs-files
        ;
      # Not in nixpkgs; see nix/packages/.
      eza-preview = pkgs.yazi-eza-preview;
    }
    // lib.optionalAttrs (!developing) localPlugins;

    # Installing a plugin only places it. Each of these also has to be turned
    # on — a setup call, a fetcher, or a key — and until that is written here
    # they sit in the plugins directory doing nothing.
    initLua = ''
      require("full-border"):setup()
      require("githead"):setup()
      require("git"):setup()
      require("gitstat"):setup()


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
          "g"
          "s"
        ];
        run = "plugin vcs-files";
        desc = "List only the files git says changed";
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

  # While `developing`, the two local plugins are links to the checkout rather
  # than copies in the store. home-manager writes the same path either way, so
  # only one of the two definitions may exist at a time.
  xdg.configFile = lib.optionalAttrs developing (
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "yazi/plugins/${name}.yazi" {
        source = config.lib.file.mkOutOfStoreSymlink "${checkout}/${name}";
      }
    ) localPlugins
  );
}
