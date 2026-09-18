_final: prev:
let
  # prev, not final: this attribute set is what the overlay contributes, so
  # resolving through final would require its own output to already exist.
  fetch = prev.fetchFromGitHub;

  # A herdr plugin root is its source tree — the manifest at the top and
  # whatever its actions name beside it — so for a plugin that ships no build
  # step, installing is copying. These are packages rather than bare
  # `fetchFromGitHub` calls so that `nix-update --flake <name>` can find a
  # `version` to bump and a `src` to re-hash; a fetch on its own gives it
  # neither, and the pins sat still for months because of it.
  # Takes either an attribute set or a function of finalAttrs, so a plugin whose
  # tag is built from its own version can still reach it.
  sourcePlugin =
    args:
    prev.stdenvNoCC.mkDerivation (
      finalAttrs:
      {
        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -R ./. $out/
          runHook postInstall
        '';
      }
      // (if builtins.isFunction args then args finalAttrs else args)
    );
in
{
  # tmux-style 1-9 numbering. Its tab naming is switched off in the module: every
  # pane here is an agent, so naming a tab after its foreground process would
  # read `claude` on all of them and flip with focus.
  herdr-automatic-rename = sourcePlugin (finalAttrs: {
    pname = "herdr-automatic-rename";
    version = "0.11.1";
    src = fetch {
      owner = "qu8n";
      repo = "herdr-automatic-rename";
      tag = "v${finalAttrs.version}";
      hash = "sha256-jgbX/WvlUAJYyVJRQ+IuC89TGC8rAISoTEofyf9IKS0=";
    };
  });

  # Writes herdr's workspace/tab/agent context out to the terminal's own title —
  # what the window manager and the app switcher show.
  #
  # No tags published, so the version is the pinned commit's date in the form
  # `nix-update --version=branch` writes back.
  herdr-window-title-sync = sourcePlugin {
    pname = "herdr-window-title-sync";
    version = "0-unstable-2026-06-26";
    src = fetch {
      owner = "rjyo";
      repo = "herdr-window-title-sync";
      rev = "b07f1140b7308d66487b2f4be546c0c7db065569";
      hash = "sha256-NyRmPI7Ja0NGVzKpMOYWXdK9rISMD5xT27XCW2z6DAw=";
    };
  };

  # A which-key for herdr's prefix: a popup listing every binding grouped and
  # labelled, where the next key runs the one shown. herdr gives plugins no way
  # to notice the prefix being pressed, so it opens on a key of its own rather
  # than on a timeout the way which-key does in Neovim.
  #
  # Pinned to the last commit. Upstream stopped after four days and says it was
  # verified against herdr 0.7.5; this is on trial against 0.9.1.
  #
  # Two changes from the repository as published. The manifest runs `python3`
  # by name, and on macOS that is a shim which fails without Command Line
  # Tools, so it is pointed at nixpkgs' interpreter. And upstream's fast route —
  # a `type = "popup"` keybinding — gets none of herdr's plugin variables, so it
  # writes a launcher into the plugin's config directory to restore them,
  # because a plugin installed by herdr lives under a path with a hash that
  # changes on reinstall. A store path does not change within a version, so the
  # launcher is built into the package instead of written at runtime.
  herdr-which-key = sourcePlugin {
    pname = "herdr-which-key";
    version = "0-unstable-2026-08-02";
    src = fetch {
      owner = "CowboyVang";
      repo = "herdr-which-key";
      rev = "7339ad4edd734b5295e5bde8375e97de9f7ccb0b";
      hash = "sha256-qar8aToFKMTTlpqfidmxBkJa3H7GFn2qWj+Gmd7ZPMY=";
    };
    nativeBuildInputs = [ prev.makeWrapper ];
    postInstall = ''
      substituteInPlace $out/herdr-plugin.toml \
        --replace-fail '"python3"' '"${prev.python3}/bin/python3"'
      makeWrapper ${prev.python3}/bin/python3 $out/libexec/which-key-show \
        --set HERDR_PLUGIN_ROOT $out \
        --set HERDR_PLUGIN_ID cowboyvang.which-key \
        --add-flags "-u $out/bin/which-key show"
    ''
    # herdr switches to an ASCII source for the length of prefix mode, and the
    # space that opens this popup is what ends prefix mode — so the input
    # method is back on kana by the time the popup reads its first key, and
    # that key becomes a kana. The launcher switches to ABC itself and hands
    # the input method back afterwards, so a herdr command taken mid-sentence
    # returns to the sentence.
    + (
      if prev.stdenv.hostPlatform.isDarwin then
        ''
          cat > $out/libexec/which-key-launch <<'LAUNCH'
          #!@shell@
          previous="$(@macism@)"
          @macism@ com.apple.keylayout.ABC
          @show@ "$@"
          status=$?
          @macism@ "$previous"
          exit "$status"
          LAUNCH
          substituteInPlace $out/libexec/which-key-launch \
            --subst-var-by shell ${prev.runtimeShell} \
            --subst-var-by macism ${prev.lib.getExe prev.macism} \
            --subst-var-by show $out/libexec/which-key-show
          chmod +x $out/libexec/which-key-launch
        ''
      else
        ''
          ln -s which-key-show $out/libexec/which-key-launch
        ''
    );
  };

  # Copying what is on screen by typing a hint over it, rather than reaching for
  # the mouse. Also built rather than fetched; see nix/packages/herdr-pluck.
  herdr-pluck = prev.callPackage ../packages/herdr-pluck { };
}
