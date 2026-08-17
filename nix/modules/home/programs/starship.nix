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

  # The preset has no nix_shell segment, and its $conda slot is dead weight here
  # — conda, mamba and micromamba are all absent, so that block never fills.
  # Take the slot: it sits directly after the language versions, and a devshell
  # is what decides which versions those are. Replacing rather than adding also
  # avoids crowding the leading block, where the OS mark and the snowflake ended
  # up welded together.
  format =
    builtins.replaceStrings
      [ "$conda" "$bun" ]
      [
        "$nix_shell"
        "$bun\${custom.pnpm}\${custom.yarn}\${custom.npm}"
      ]
      preset.format;

  # By codepoint, not as a literal character: Nerd Font glyphs sit in the
  # Unicode private use area, where they are invisible in diffs and were already
  # lost once in transit here. `\uXXXX` is not a Nix escape, so JSON decodes it.
  glyph = code: builtins.fromJSON ''"\u${code}"'';
  nixGlyph = glyph "f313"; # nf-linux-nixos

  # Which package manager a directory belongs to, decided the way the tools
  # themselves decide it: by lockfile. starship has no module for this — $nodejs
  # reports the runtime, not the manager — so each is a custom module keyed on
  # the file that would make the command correct.
  #
  # It earns its place: pnpm, npm and yarn each appear thirteen times in this
  # shell's history and bun six, and the history also holds `npm i --frozen`,
  # which is a yarn flag typed into npm. The lockfile is on screen either way;
  # this puts it where the mistake happens.
  pm = symbol: lockfiles: {
    inherit symbol;
    detect_files = lockfiles;
    style = "bg:green";
    # Two trailing spaces, where the language modules beside these use one. Those
    # end in a version string; these end in the glyph itself, and the separator
    # that follows is drawn with a negative left bearing — it reaches back into
    # the cell before it, eating a single space almost entirely.
    format = "[[ $symbol  ](fg:crust bg:green)]($style)";
    # No `when`: as a boolean it means "always", which overrides detect_files
    # and puts all three managers on every prompt. Leaving it unset lets the
    # lockfile alone decide. No `command` either — the file's presence is the
    # whole answer, and spawning a process each prompt to restate it would not
    # be worth the latency.
    description = "package manager in use";
  };
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
      # decides what every tool on PATH resolves to. It inherits the sapphire
      # block conda vacated, padded the way conda was. $name is omitted: for
      # `nix develop` it resolves to the placeholder `nix-shell-env`, which names
      # no particular shell.
      nix_shell = {
        disabled = false;
        # starship's default is the emoji ❄️, which renders wide and in its own
        # colours beside a bar that is otherwise all Nerd Font.
        symbol = nixGlyph;
        style = "fg:crust bg:sapphire";
        # Two spaces after the symbol, one before, where every other segment uses
        # one on each side. The glyph's ink sits to the left of its cell — the
        # separator ahead of it crowds, the one behind it does not — and advance
        # widths across the font are identical, so padding is the only lever.
        format = "[ $symbol  ]($style)";
        heuristic = false;
      };

      # bun is absent here on purpose: starship's own $bun module already fires
      # on the same lockfiles and reports a version besides, so adding it would
      # print the mark twice. The cost is that bun alone shows a version where
      # the other three show an icon — worth it for the version, and for not
      # duplicating the glyph.
      #
      # All three marks come from devicons, so they share a hand. The Seti set
      # carries yarn and npm too, but its npm glyph is the .npmignore mark
      # rather than the manager's, and mixing the two sets shows.
      custom = {
        pnpm = pm (glyph "e865") [ "pnpm-lock.yaml" ]; # dev-pnpm
        yarn = pm (glyph "e8ec") [ "yarn.lock" ]; # dev-yarn
        npm = pm (glyph "e71e") [ "package-lock.json" ]; # dev-npm
      };

      # Nothing on this machine provides conda, so its block could only ever be
      # empty; nix_shell now stands where it did.
      conda.disabled = true;

      # The preset gives [os] no format, so starship's default applies and the
      # symbol renders with no padding at all. That went unnoticed while
      # $username sat next to it supplying a leading space of its own — turning
      # show_always off below removed the padding as a side effect, leaving the
      # OS mark welded to the separator.
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
