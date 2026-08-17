{ pkgs, ... }:
let
  # starship ships a Catppuccin powerline preset, already defaulting to the
  # mocha palette this machine uses everywhere else. Taking it whole means the
  # Nerd Font glyphs — powerline separators, the per-OS marks, the language
  # icons — come out of the package rather than being typed here. That matters:
  # they live in the Unicode private use area and above U+FFFF, where they are
  # invisible in diffs and easy to mangle in transit.
  presetName = "catppuccin-powerline";
  preset = builtins.fromTOML (
    builtins.readFile "${pkgs.starship}/share/starship/presets/${presetName}.toml"
  );

  # The preset has no nix_shell segment. Rather than retype the whole bar to add
  # one, splice it into the preset's own format string, immediately before the
  # directory it qualifies.
  format = builtins.replaceStrings [ "$directory" ] [ "$nix_shell$directory" ] preset.format;
in
{
  programs.starship = {
    enable = true;

    # This configuration writes fish's init by hand in fish/config.fish rather
    # than through programs.fish, so the generated integration snippet has
    # nowhere to land. config.fish calls `starship init fish` itself.
    enableFishIntegration = false;

    # Merged by home-manager at build time, with `settings` layered on top.
    presets = [ presetName ];

    settings = {
      inherit format;

      # Whether this shell sits inside a devshell is invisible otherwise, and it
      # decides what every tool on PATH resolves to. Styled to match the segment
      # it now shares with $os. $name is omitted: for `nix develop` it resolves
      # to the placeholder `nix-shell-env`, which names no particular shell.
      nix_shell = {
        disabled = false;
        style = "bg:red fg:crust";
        format = "[$symbol ]($style)";
        heuristic = false;
      };

      # The preset sets show_always, which pins the local username to every
      # prompt. On this machine it never varies, so it reports nothing. Leaving
      # the module enabled but not always-on keeps the segment for the cases it
      # was meant for: root, and shells opened over SSH.
      username.show_always = false;

      # The preset draws one line; put the command on its own so a long path
      # never pushes what is being typed off to the right. Its format already
      # contains $line_break, so this is the only switch needed.
      line_break.disabled = false;

      cmd_duration = {
        min_time = 1000;
        show_milliseconds = false;
        # The preset raises a desktop notification after 45s. Nothing here asked
        # for that, and it fires from every shell on the machine.
        show_notifications = false;
      };
    };
  };
}
