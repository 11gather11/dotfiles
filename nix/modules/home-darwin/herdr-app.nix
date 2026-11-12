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
  # made is not made again.
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
  mdAsset = pkgs.writeShellApplication {
    name = "md-asset";
    runtimeInputs = [ pkgs.mermaid-cli ];
    text = ''
      # usage: md-asset mermaid <source.mmd> <out.png>
      #        md-asset image   <source>     <out>
      #        md-asset svg     <source.svg> <out.png> <color> [longest side]
      kind="$1" src="$2" out="$3"
      if [ ! -s "$out" ]; then
        mkdir -p "$(dirname "$out")"
        case "$kind" in
          mermaid)
            PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
              mmdc --quiet -p ${puppeteerConfig} -c ${mermaidConfig} \
              -i "$src" -o "$out" -b transparent -s 2 >&2
            ;;
          image) cp "$src" "$out" ;;
          svg)
            # Rasterised here at the size it is shown, as the app draws an
            # SVG at its own size and enlarging that blurs it; twice its own
            # size (at most 2048) when no size is asked for. currentColor,
            # the text colour an icon is meant to take, becomes the theme's,
            # or it draws black on the dark background.
            color="$4"
            max="''${5:-$(/usr/bin/sips -g pixelWidth -g pixelHeight "$src" \
              | awk '/pixel(Width|Height)/ { if ($2 > m) m = $2 } END { m *= 2; print int(m > 2048 ? 2048 : m) }')}"
            sed "s/currentColor/$color/g" "$src" > "$out.svg"
            /usr/bin/sips -s format png -Z "$max" "$out.svg" --out "$out" >/dev/null
            rm -f "$out.svg"
            ;;
          *) echo "md-asset: unknown kind: $kind" >&2; exit 2 ;;
        esac
      fi
      # Only the cache's own files: an image's source is the document's, and
      # its date is not this cache's to change.
      touch "$out"
      if [ "$kind" = mermaid ]; then touch "$src"; fi
      find "$(dirname "$out")" -type f -mtime +14 -delete
      /usr/bin/sips -g pixelWidth -g pixelHeight "$out" \
        | awk '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { print w, h }'
    '';
  };

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
        rsync --recursive --checksum --delete \
          --exclude gpui-kit.d.ts --exclude herdr.d.ts --exclude jsconfig.json \
          "$d" "$dst/mods/$name/"
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
    pkgs.llm-agents.herdr-core
    harnessStatus
    herdrAppSync
    mdAsset
  ];

  # The file tree's icons. A mod can draw an image only from a path under the
  # app's folder, so the package is linked in rather than read from the store.
  xdg.configFile."herdr-app/file-icons".source = pkgs.material-icon-theme;

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
