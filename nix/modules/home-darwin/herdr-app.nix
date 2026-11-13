{
  pkgs,
  lib,
  config,
  helpers,
  dotfilesDir,
  ...
}:
let
  appHome = "${config.xdg.configHome}/herdr-app";

  # The app installs from the herdr-app cask (darwin-system/homebrew.nix) and
  # writes settings.json itself — zoom, window state, what Settings changes —
  # so only the keys owned here are merged in, and the rest is left as the app
  # wrote it.
  settings = {
    # On when absent: a daily report of usage counts. Off, as for every other
    # tool here, and turning it off also deletes reports not yet sent.
    telemetry = false;

    # The scheme every other tool here is set to. herdr-app ships no Catppuccin,
    # so the file is herdr-app/themes/catppuccin-mocha.json, linked below.
    # settings.json's theme applies wherever a layout names none, which the
    # shipped `main` and `terminals` layouts do not.
    theme = "catppuccin-mocha";

    # Ghostty's family. The size is one below Ghostty's 13: herdr-app draws the
    # same face with heavier strokes and wider cells, and 12 reads closer to
    # it. The layouts leave fonts unset, which is what lets this apply to all
    # of them.
    font = "PlemolJP Console NF";
    font_size = 12;

    # The panels' text too (sidebars, tab bar, the harness panel), so the
    # window has one typeface rather than Geist around a PlemolJP terminal.
    # Each mod still sets its own text sizes.
    ui_font = "PlemolJP Console NF";

    # Ghostty's macos-option-as-alt for the same reason given there: snacks and
    # other terminal programs bind alt+letter. "auto" would do this only on a US
    # or ABC layout, and the input source here switches to Japanese.
    option_as_alt = "on";
  };

  mergeConfig = helpers.mergeConfig pkgs;

  # What the harness panel (herdr-app/mods/harness) runs: issue-harness's own
  # snapshot of a repository, so the panel draws the scripts' verdicts rather
  # than reimplementing them in JavaScript. The scripts are taken from this
  # repository at build time, the same files the installed skill carries, and
  # nushell is named here because it is not on PATH.
  harnessStatus = pkgs.writeShellApplication {
    name = "harness-status";
    runtimeInputs = [ pkgs.nushell ];
    text = ''
      exec nu ${../../../agents/skills/issue-harness/scripts}/status.nu "$@"
    '';
  };

  # herdr-core with Claude Code's per-session variables removed from what it
  # is started with. Whatever first runs `hc` starts the core when none is
  # running, and the core hands its own environment to every terminal it
  # opens, for as long as it runs (`hc run` does not pass the caller's). A core
  # first started from a Claude Code Bash call therefore gave every later tab
  # and worker that session's identity: CLAUDE_CODE_CHILD_SESSION, which makes
  # each Claude started there skip saving its transcript, CLAUDECODE, the
  # session's id and its messaging socket and token. Removed for every call,
  # since one that does not start the core passes none of it on anyway.
  herdrCore = pkgs.symlinkJoin {
    name = "herdr-core-${pkgs.llm-agents.herdr-core.version}";
    paths = [ pkgs.llm-agents.herdr-core ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild =
      let
        unset = lib.concatMapStringsSep " " (v: "--unset ${v}") [
          "CLAUDECODE"
          "CLAUDE_CODE_CHILD_SESSION"
          "CLAUDE_CODE_ENTRYPOINT"
          "CLAUDE_CODE_EXECPATH"
          "CLAUDE_CODE_MESSAGING_SOCKET"
          "CLAUDE_CODE_MESSAGING_TOKEN"
          "CLAUDE_CODE_SESSION_ATTENDED"
          "CLAUDE_CODE_SESSION_ID"
          "CLAUDE_EFFORT"
          "CLAUDE_PID"
        ];
      in
      # Each wrapper runs the package's own file rather than a renamed copy
      # (wrapProgram's .hc-wrapped): hc reads its name from the path it runs
      # from, and its help would otherwise call it `.hc-wrapped`.
      ''
        for bin in hc herdr-core; do
          rm "$out/bin/$bin"
          makeWrapper "${pkgs.llm-agents.herdr-core}/bin/$bin" "$out/bin/$bin" ${unset}
        done
      '';
  };

  # Starts Claude again, in its own conversation, in each terminal that lost
  # it: what the herdr TUI's resume_agents_on_restore did. herdr-core keeps
  # its terminals and their labels when the core is stopped or the machine
  # restarts, and puts a shell back where the program was, but does not start
  # the program again. The hook in the claude-code module labels each terminal
  # with the conversation it holds (claude.session) and drops the label when
  # the person ends the session, so a label on a terminal sitting at its shell
  # prompt is a conversation lost by something else.
  #
  # The agents panel runs this every few seconds, which covers both a stopped
  # core (the window stays open) and a restart (the panel starts with it).
  # Each id is sent once (claude.resumed): a resume that fails leaves the
  # terminal at its prompt, and sending it again would only fail again.
  claudeResume = pkgs.writeShellApplication {
    name = "claude-resume";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      # Run from a terminal, hc send would wrap the command in
      # <hc from="t…">…</hc>, its envelope for one agent messaging another,
      # which the shell reads as a redirection. Without the sender's identity
      # it types the text as given.
      unset HC_TERMINAL_ID HC_TERMINAL_SOCKET

      # Terminals at a shell prompt, not in a program the person is using. A
      # shell by name rather than the argv the terminal started with: one
      # started with a command (the harness button, a worker) gets a login
      # shell back in its place, not that command.
      hc ls --json | jq -r '
        (if type == "array" then . else .terminals end)[]
        | select(.state == "live" and (.agent | IN("fish", "zsh", "bash", "sh")))
        | .address' |
        while read -r terminal; do
          # hc ls leaves labels out; hc get of one terminal has them.
          # The session, and the repository when it was its harness.
          read -r id harness < <(hc get "$terminal" --json | jq -r '
            (.labels // {}) as $l
            | select(($l["claude.session"] // "") != "" and $l["claude.resumed"] != $l["claude.session"])
            | "\($l["claude.session"]) \($l["harness"] // "")"') || true
          [ -n "''${id:-}" ] || continue
          hc label "$terminal" "claude.resumed=$id" >/dev/null
          # A harness comes back as one: its label stayed (only the person
          # ending it removes it, see hc-session.sh), and Remote Control is
          # turned on again under the name `harness` gives it, so the phone
          # finds the same session.
          if [ -n "''${harness:-}" ]; then
            hc send "$terminal" "claude --resume $id --remote-control \"$(basename "$harness") harness\"" >/dev/null
          else
            hc send "$terminal" "claude --resume $id" >/dev/null
          fi
          echo "$terminal $id"
        done
    '';
  };

  # Starts the harness's Claude with Remote Control, so the Claude app on the
  # phone can talk to it: ask how the workers are doing, hand it an issue,
  # answer what it brings to the person. Only the harness is reachable; the
  # workers stay local and are reached through it, so the phone's session list
  # holds one session per repository rather than one per worker.
  #
  # Named after the repository, which is what tells two harnesses apart in that
  # list. Words after `harness` become the opening request to /issue-harness.
  harness = pkgs.writeShellApplication {
    name = "harness";
    runtimeInputs = [ pkgs.git ];
    #
    # In a herdr-core terminal it labels the terminal harness=<repository>,
    # which is how the panels tell a harness from any other Claude, whatever
    # started it: the terminal's own command is the shell when `harness` is
    # typed into one. The label stays until the person ends the session
    # (hc-session.sh), so a harness lost to a stopped core or a restart is
    # resumed as one (claude-resume).
    text = ''
      root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      repo=$(basename "$root")
      if [ -n "''${HC_TERMINAL_ID:-}" ]; then
        hc label "$HC_TERMINAL_ID" "harness=$root" >/dev/null 2>&1 || true
      fi
      if [ $# -gt 0 ]; then
        claude --remote-control "$repo harness" "/issue-harness $*"
      else
        claude --remote-control "$repo harness"
      fi
    '';
  };

  # Copies herdr-app/ from the working tree into the app's folder, which the
  # app redraws from as files there change. Run by every switch, and by hand
  # to try an edit in the window at once.
  #
  # Copied, not linked: the app learns of a change from the file system's
  # events under its own folder, and an edit behind a symbolic link happens at
  # the link's target, so a linked mod kept running its old code until the
  # link itself was replaced. The cost is that a change made through the app's
  # Settings (to keys.json, say) lasts only until the next sync; anything worth
  # keeping goes into the repository.
  #
  # keys.json is the whole file, not a merge: any edit makes the file the
  # person's, and from then on the app stops adding its new default keys
  # anyway. So the defaults of the release it was taken from are written out in
  # full, and a release's new keys are taken in by hand.
  # Turns what herdr-app's markdown view cannot draw into images it can: a
  # Mermaid block rendered to PNG, a picture the document links to copied in
  # (a mod draws images only from under the app's folder). Prints the image's
  # size in pixels, which the viewer needs to lay it out; an image already
  # made is not made again. It also prints how many pixels it drew per point,
  # which the viewer divides by: a vector source is drawn at twice its size,
  # sharp on a Retina screen, and kept in `<image>.scale` for later runs.
  #
  # The viewer asks for every image each time it shows a document, so the date
  # of a file in the cache is when it was last shown. Each run marks what it
  # served and removes what has not been shown for a fortnight: the cache keeps
  # what is read and does not grow with every diagram ever opened.
  #
  # Mermaid is rendered by mermaid-cli in Google Chrome, installed by the
  # google-chrome cask: nixpkgs' mermaid-cli carries no browser on macOS.
  mermaidConfig = (pkgs.formats.json { }).generate "mermaid-config.json" {
    theme = "dark";
    themeVariables.fontFamily = "PlemolJP Console NF, sans-serif";
  };
  puppeteerConfig = (pkgs.formats.json { }).generate "puppeteer-config.json" {
    headless = "shell";
  };
  # MathJax sizes its SVG in ex and draws past its viewBox (limits, accents),
  # which a rasteriser clips: this pads the viewBox by a fifth of its height
  # on every side and sizes it in px.
  mathjaxFit = pkgs.writeText "mathjax-fit.pl" ''
    my $px = 9;    # px per ex
    undef $/; $_ = <STDIN>;
    my ($vx, $vy, $vw, $vh) = /viewBox="([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+)"/;
    my ($w) = /width="([\d.]+)ex"/;
    my ($h) = /height="([\d.]+)ex"/;
    my $m = $vh * 0.2;
    s/viewBox="[^"]*"/sprintf('viewBox="%.1f %.1f %.1f %.1f"', $vx - $m, $vy - $m, $vw + 2 * $m, $vh + 2 * $m)/e;
    s/width="[\d.]+ex"/sprintf('width="%.1fpx"', ($w + 2 * $m * $w \/ $vw) * $px)/e;
    s/height="[\d.]+ex"/sprintf('height="%.1fpx"', $h * ($vh + 2 * $m) \/ $vh * $px)/e;
    print;
  '';
  mdAsset = pkgs.writeShellApplication {
    name = "md-asset";
    runtimeInputs = [
      pkgs.mermaid-cli
      pkgs.mathjax-node-cli
      pkgs.curl
      pkgs.perl
    ];
    text = ''
      # usage: md-asset mermaid <source.mmd> <out.png>
      #        md-asset image   <source>     <out>
      #        md-asset svg     <source.svg> <out.png> <color> [longest side]
      #        md-asset math    <source.tex> <out.png> <color>
      #        md-asset url     <url>        <out.png> <color>
      kind="$1" src="$2" out="$3"

      # An SVG rasterised at the size it is shown, as the app draws an SVG at
      # its own size and enlarging that blurs it; twice its own size (at most
      # 2048) when no size is asked for. currentColor, the text colour an icon
      # or a formula is meant to take, becomes the theme's, or it draws black
      # on the dark background.
      rasterise() { # <svg> <out.png> <color> [longest side]
        local max="''${4:-$(/usr/bin/sips -g pixelWidth -g pixelHeight "$1" \
          | awk '/pixel(Width|Height)/ { if ($2 > m) m = $2 } END { m *= 2; print int(m > 2048 ? 2048 : m) }')}"
        sed "s/currentColor/$3/g" "$1" > "$2.svg"
        /usr/bin/sips -s format png -Z "$max" "$2.svg" --out "$2" >/dev/null
        rm -f "$2.svg"
        # At twice its size unless a size was asked for.
        if [ -n "''${4:-}" ]; then echo 1 > "$2.scale"; else echo 2 > "$2.scale"; fi
      }

      if [ ! -s "$out" ]; then
        mkdir -p "$(dirname "$out")"
        case "$kind" in
          mermaid)
            PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
              mmdc --quiet -p ${puppeteerConfig} -c ${mermaidConfig} \
              -i "$src" -o "$out" -b transparent -s 2 >&2
            echo 2 > "$out.scale"
            ;;
          image) cp "$src" "$out" && echo 1 > "$out.scale" ;;
          svg) rasterise "$src" "$out" "$4" "''${5:-}" ;;
          math)
            tex2svg "$(cat "$src")" 2>/dev/null | perl ${mathjaxFit} > "$out.math.svg"
            rasterise "$out.math.svg" "$out" "$4"
            rm -f "$out.math.svg"
            ;;
          url)
            curl --silent --fail --location --max-time 20 --output "$out.download" "$src"
            # A badge or diagram served as SVG is drawn like any SVG; a bitmap
            # becomes a PNG, the one format every source can be kept as.
            if head -c 1024 "$out.download" | grep -q '<svg'; then
              # sips reads an SVG by its extension, which a URL may lack.
              mv "$out.download" "$out.download.svg"
              rasterise "$out.download.svg" "$out" "$4"
              rm -f "$out.download.svg"
            else
              /usr/bin/sips -s format png "$out.download" --out "$out" >/dev/null
              echo 1 > "$out.scale"
            fi
            rm -f "$out.download"
            ;;
          *) echo "md-asset: unknown kind: $kind" >&2; exit 2 ;;
        esac
      fi
      # Only the cache's own files: an image's source is the document's, and
      # its date is not this cache's to change.
      touch "$out"
      if [ -e "$out.scale" ]; then touch "$out.scale"; fi
      case "$kind" in mermaid | math) touch "$src" ;; esac
      find "$(dirname "$out")" -type f -mtime +14 -delete
      /usr/bin/sips -g pixelWidth -g pixelHeight "$out" \
        | awk -v s="$(cat "$out.scale" 2>/dev/null)" \
          '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { print w, h, (s == "" ? 1 : s) }'
    '';
  };

  # GitHub's emoji shortcodes (`:tada:`) as `{alias: emoji}`, from gemoji,
  # GitHub's own list, for the viewer to put the emoji in their place: the
  # markdown view draws the shortcode as text.
  emojiMap = pkgs.runCommand "emoji-map.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -c '[.[] | select(.emoji) as $e | $e.aliases[] | {key: ., value: $e.emoji}] | from_entries' \
      ${pkgs.rubyPackages.gemoji}/lib/ruby/gems/*/gems/gemoji-*/db/emoji.json > $out
  '';

  herdrAppSync = pkgs.writeShellApplication {
    name = "herdr-app-sync";
    runtimeInputs = [ pkgs.rsync ];
    text = ''
      src=${lib.escapeShellArg "${dotfilesDir}/herdr-app"}
      dst=${lib.escapeShellArg appHome}

      # A link left by the earlier linked layout would have rsync write
      # through it into the repository.
      unlink_old() { if [ -L "$1" ]; then rm "$1"; fi; }

      # The paths below are relative to the repository folder: keys.json, and
      # every layout and theme in it.
      cd "$src"
      for f in keys.json layouts/*.json themes/*.json; do
        [ -e "$src/$f" ] || continue
        mkdir -p "$(dirname "$dst/$f")"
        unlink_old "$dst/$f"
        rsync --checksum "$src/$f" "$dst/$f"
      done

      for d in "$src"/mods/*/; do
        name="$(basename "$d")"
        unlink_old "$dst/mods/$name"
        mkdir -p "$dst/mods/$name"
        # The app writes these type files into every mod folder; they are
        # its, not the repository's, and --delete must leave them alone.
        # lib/ is filled below.
        rsync --recursive --checksum --delete \
          --exclude gpui-kit.d.ts --exclude herdr.d.ts --exclude jsconfig.json \
          --exclude /lib/ \
          "$d" "$dst/mods/$name/"

        # Code more than one mod uses (the UI parts, the folder the panels
        # follow) lives once, in herdr-app/lib, and is copied into
        # each mod that imports it: the app refuses an import from outside a
        # mod's own folder. Only into those, and by checksum, because any
        # file saved under a mod reloads it.
        if grep -q "from '\./lib/" "$d"main.js; then
          rsync --recursive --checksum --delete "$src/lib/" "$dst/mods/$name/lib/"
        elif [ -d "$dst/mods/$name/lib" ]; then
          rm -r "$dst/mods/$name/lib"
        fi
      done
    '';
  };
in
{
  # The engine the app is a client of (`hc`): it runs the terminals and agents
  # and outlives the window. Separate from the herdr TUI this machine also
  # runs. The app finds it on PATH; without it the app offers to curl an
  # installer into ~/.local/bin, outside this configuration.
  home.packages = [
    herdrCore
    claudeResume
    harness
    harnessStatus
    herdrAppSync
    mdAsset
  ];

  # The file tree's icons. A mod can draw an image only from a path under the
  # app's folder, so the package is linked in rather than read from the store.
  xdg.configFile."herdr-app/file-icons".source = pkgs.material-icon-theme;
  xdg.configFile."herdr-app/emoji.json".source = emojiMap;

  home.activation = {
    writeHerdrAppSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${mergeConfig} ${lib.escapeShellArg "${appHome}/settings.json"} ${
        (pkgs.formats.json { }).generate "herdr-app-settings.json" settings
      }
    '';

    syncHerdrAppFiles = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD ${lib.getExe herdrAppSync}
    '';
  };
}
