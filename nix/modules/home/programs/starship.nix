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

  # The preset has no nix_shell segment, so splice it into the preset's own
  # format string rather than retyping the bar — beside $os, the other thing
  # describing this machine rather than the work in front of it.
  format = builtins.replaceStrings [ "$username" ] [ "$username$nix_shell" ] preset.format;

  # By codepoint, not as a literal character: Nerd Font glyphs sit in the
  # Unicode private use area, where they are invisible in diffs and were already
  # lost once in transit here. `\uXXXX` is not a Nix escape, so JSON decodes it.
  nixGlyph = builtins.fromJSON ''"\uf313"''; # nf-linux-nixos
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
        # starship's default is the emoji ❄️, which renders wide and in its own
        # colours beside a bar that is otherwise all Nerd Font.
        symbol = nixGlyph;
        style = "bg:red fg:crust";
        # Two trailing spaces, against the single space every other segment ends
        # on. The glyph fills far more of its cell than a letter does, so one
        # space reads as none beside it — measured advance widths are identical,
        # so this is about ink, not metrics.
        format = "[$symbol  ]($style)";
        heuristic = false;
      };

      # The preset gives [os] no format, so starship's default applies and the
      # symbol renders with no padding at all. That went unnoticed while
      # $username sat next to it supplying a leading space of its own — turning
      # show_always off below removed the padding as a side effect, leaving the
      # OS mark welded to whatever follows it.
      os.format = "[$symbol ]($style)";

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
