{ helpers, ... }:
let
  # Catppuccin Mocha, the same palette the terminal and editor use.
  inherit (helpers.theme) starshipPalette;
in
{
  programs.starship = {
    enable = true;

    # This configuration writes fish's init by hand in fish/config.fish rather
    # than through programs.fish, so the generated integration snippet has
    # nowhere to land. config.fish calls `starship init fish` itself.
    enableFishIntegration = false;

    settings = {
      # Two lines: everything informational above, only the cursor below, so a
      # long path never pushes the command being typed off to the right.
      format = ''
        $directory$git_branch$git_status$git_state$nix_shell$cmd_duration
        $character'';

      add_newline = true;

      character = {
        success_symbol = "[❱](green)";
        error_symbol = "[❱](red)";
        vimcmd_symbol = "[❰](peach)";
      };

      directory = {
        style = "blue bold";
        truncation_length = 3;
        truncate_to_repo = true;
        # A repository root is the unit of work here, so mark it rather than
        # letting it read as just another path segment.
        repo_root_style = "blue bold underline";
        format = "[$path]($style)[$read_only]($read_only_style) ";
      };

      git_branch = {
        style = "mauve";
        # Trailing space: without it the status symbols butt against the branch
        # name and read as part of it — `front-e2e-bs-desktop$»+`.
        format = "[$branch]($style) ";
      };

      # Symbols rather than counts: the question at the prompt is "is there
      # anything uncommitted", and `git status` answers the rest.
      git_status = {
        style = "peach";
        format = "[$all_status$ahead_behind]($style) ";
        conflicted = "=";
        ahead = "↑\${count}";
        behind = "↓\${count}";
        diverged = "↕↑\${ahead_count}↓\${behind_count}";
        untracked = "?";
        stashed = "\\$";
        modified = "•";
        staged = "+";
        renamed = "»";
        deleted = "✘";
      };

      # Rebase, merge, bisect: states where the next command depends on knowing
      # you are in them.
      git_state = {
        style = "red bold";
        format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";
      };

      # The reason a Nix user needs a prompt module at all: whether this shell
      # is inside a devshell is invisible otherwise, and it changes what every
      # tool on PATH resolves to.
      nix_shell = {
        style = "teal";
        format = "[$symbol]($style) ";
        # Symbol only. $name is the derivation's name, which for `nix develop`
        # is the placeholder `nix-shell-env` — it takes width without saying
        # which shell this is. Being inside one at all is the whole signal.
        symbol = "❄";
        # Off: the heuristic infers "in a Nix shell" from the environment, and
        # on a nix-darwin machine every binary already lives in /nix/store, so
        # it fires in every shell. IN_NIX_SHELL is the honest signal.
        heuristic = false;
      };

      cmd_duration = {
        min_time = 1000;
        style = "yellow";
        format = "[$duration]($style) ";
      };

      palette = "catppuccin_mocha";
      palettes.catppuccin_mocha = starshipPalette;
    };
  };
}
