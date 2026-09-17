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

  # Renders a real Chromium view in a pane over CDP, so an agent's browser work
  # is visible and steerable instead of happening headless behind a screenshot.
  # No runtime dependencies — its package.json declares none — so fetching the
  # source is the whole build.
  #
  # Pinned deliberately, and excluded from the update workflow. Upstream has
  # since deprecated this in favour of zenbu-labs/terminal-browser, and the
  # commit that did so also deleted herdr-plugin.toml: a later revision builds
  # fine and then registers nothing, because there is no manifest for `herdr
  # plugin link` to read. This revision is the last one that is still a plugin.
  #
  # The successor was tried and is not ready here, so this stays until it is.
  # pkgs.llm-agents.terminal-browser does not launch: Nix rewrites the Electron
  # bundle, which breaks the signature seal on Electron Framework.framework, and
  # macOS reports the app as damaged. Its own release tarball is unsigned from
  # the browser's point of view and trips Gatekeeper's quarantine instead. That
  # package is also on 0.8.1 while upstream has moved to 0.11.1, and its herdr
  # plugin offers neither --target-pane nor --no-focus, both of which the
  # markdown preview in nvim/lua/plugins/markdown.lua depends on.
  herdr-browser = sourcePlugin {
    pname = "herdr-browser";
    version = "0-unstable-2026-07-28";
    src = fetch {
      owner = "ogulcancelik";
      repo = "herdr-browser";
      rev = "be6888b71cf4eb5939ee79a746bd1a1c22ade046";
      hash = "sha256-4Dlo4YQpLPJKEPuXSS4EO5LMCmUn/tezEiIqlFXhCxo=";
    };
  };

  # Reviewing an agent's diff in a pane, and sending the comments written there
  # back to the agent that wrote the code. Built here rather than fetched, so
  # it has a package of its own; see nix/packages/herdr-hunk-diff.
  herdr-hunk-diff = prev.callPackage ../packages/herdr-hunk-diff { };

  # Copying what is on screen by typing a hint over it, rather than reaching for
  # the mouse. Also built rather than fetched; see nix/packages/herdr-pluck.
  herdr-pluck = prev.callPackage ../packages/herdr-pluck { };
}
