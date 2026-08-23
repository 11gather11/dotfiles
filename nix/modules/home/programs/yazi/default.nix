# TUI file manager, for the two things the shell here does not cover: renaming
# a batch of files, and moving between two directories that are not ~/Downloads
# (which dlmv handles).
{
  lib,
  pkgs,
  helpers,
  ...
}:
let
  # The palette's own diff colours, as arguments. delta below runs with
  # --no-gitconfig, so the [delta] section that carries these for `git diff`
  # does not reach it.
  deltaColours = lib.escapeShellArgs (
    lib.mapAttrsToList (name: style: "--${name}=${style}") helpers.theme.delta
  );

  # The preview pane, for a file git knows about: the whole file, with the
  # lines that changed carrying a green background. The status letters in the
  # listing say a file changed; this says what changed, without a keypress.
  gitPreview = pkgs.writeShellApplication {
    name = "yazi-git-preview";
    runtimeInputs = with pkgs; [
      git
      delta
      bat
      gawk
    ];
    text = ''
      target=''${1:-}
      # The width is an argument rather than the environment variable piper
      # also offers, because faster-piper decides whether to throw the cache
      # away on a resize by looking for $w in the command it was given. Read it
      # out of the environment and a wider pane keeps the narrower rendering.
      width=''${2:-80}
      [ -n "$target" ] || exit 0

      name=$(basename -- "$target")
      cd -- "$(dirname -- "$target")" || exit 0

      # Every path out of here that has no diff to show falls back to this, so
      # an unchanged file looks the way it did before any of this existed.
      plain() {
        exec bat --color=always --style=numbers --paging=never \
          --terminal-width="$width" -- "$name"
      }

      git rev-parse --is-inside-work-tree >/dev/null 2>&1 || plain

      base=$(git rev-parse --verify -q HEAD >/dev/null 2>&1 && echo HEAD || true)

      # -U99999 asks for the whole file as context, which is the difference
      # between a diff and a file with the changes marked in it.
      if git ls-files --error-unmatch -- "$name" >/dev/null 2>&1; then
        diff=$(git diff -U99999 ''${base:+"$base"} -- "$name")
      else
        diff=$(git diff -U99999 --no-index --src-prefix=a/ --dst-prefix=b/ \
          -- /dev/null "$name" || true)
      fi
      [ -n "$diff" ] || plain

      # --no-gitconfig: the [delta] settings are written for reading a diff in
      # a full terminal — side-by-side above all — and none of them suit a
      # narrow pane showing a file. The gutter matches bat's so that the two
      # halves of plain() and this line up.
      printf '%s\n' "$diff" | delta \
        --no-gitconfig --dark --paging=never \
        --syntax-theme "${helpers.theme.bat}" \
        ${deltaColours} \
        --file-style omit --hunk-header-style omit \
        --line-numbers --line-numbers-left-format "" \
        --line-numbers-right-format "{np:>4} " \
        --width "$width" |
        gawk -v width="$width" '
          # delta colours the rest of a changed line by asking the terminal to
          # erase to the end of it. A preview pane is not a terminal and drops
          # the request, so the background would stop at the last character.
          # Replace it with the spaces it stands for.
          BEGIN { esc = sprintf("%c", 27) }
          {
            bare = $0
            gsub(esc "\\[[0-9;]*[A-Za-z]", "", bare)
            pad = ""
            for (i = length(bare); i < width; i++) { pad = pad " " }
            gsub(esc "\\[0K", pad)
            print
          }
        '
    '';
  };

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
      # Runs a command and uses its output as the preview; how the git diff
      # below gets into the preview pane. The faster- variant because piper
      # itself re-runs the command for every line scrolled.
      faster-piper = pkgs.yazi-faster-piper;
      # Written here; see ./gitstat.
      gitstat = ./gitstat;
    };

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
          # Same mime patterns yazi sends to its own `code` previewer, so the
          # files that were shown as source are the ones shown as source with
          # their changes marked. Images, PDFs and archives keep their own.
          {
            mime = "text/*";
            run = ''faster-piper -- ${pkgs.lib.getExe gitPreview} "$1" $w'';
          }
          {
            mime = "application/{mbox,javascript,wine-extension-ini}";
            run = ''faster-piper -- ${pkgs.lib.getExe gitPreview} "$1" $w'';
          }
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
}
