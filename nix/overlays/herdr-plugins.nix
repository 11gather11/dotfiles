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

  # Copying what is on screen by typing a hint over it, rather than reaching for
  # the mouse. Also built rather than fetched; see nix/packages/herdr-pluck.
  herdr-pluck = prev.callPackage ../packages/herdr-pluck { };

  # worktrunk (`wt`) from inside herdr: an fzf picker over the worktrees and
  # branches of the repository the workspace is in, opening the checkout as a
  # tab or as a native worktree workspace. herdr has worktree commands of its
  # own, but no hook system, and the hooks are the reason `wt` is used here.
  #
  # Plain bash calling `wt`, `fzf` and `jq`, which the manifest expects on PATH
  # rather than naming by path — all three are installed here, so the scripts
  # are copied as they are.
  herdr-worktrunk = sourcePlugin (finalAttrs: {
    pname = "herdr-worktrunk";
    version = "0.7.0";
    src = fetch {
      owner = "devashish2203";
      repo = "herdr-worktrunk";
      tag = "v${finalAttrs.version}";
      hash = "sha256-Tx++zTQ1z4H8dLdCjOZ1yX9QGY/i6M3Yvi39KGHDoH4=";
    };
  });

  # Neovim in a full-height sidebar pane, its file picker as an overlay, and a
  # key to hand the file under the cursor to an agent. Built rather than
  # fetched; see nix/packages/herdr-nvim.
  herdr-nvim = prev.callPackage ../packages/herdr-nvim { };

  # An fzf palette over every action every installed plugin exposes, for the
  # ones that are not worth a key of their own. Plain bash and fzf, both of
  # which the manifest expects on PATH.
  #
  # No tags published, so the version is the pinned commit's date in the form
  # `nix-update --version=branch` writes back.
  herdr-command-palette = sourcePlugin {
    pname = "herdr-command-palette";
    version = "0-unstable-2026-06-29";
    src = fetch {
      owner = "JanTvrdik";
      repo = "herdr-command-palette";
      rev = "eab940018c2135ac23718efa11e23e9dddcd2a75";
      hash = "sha256-A43Dl365S/5w2wrttV1RnQ1g7YRJmsD3tb5EUUZcQQY=";
    };
  };

  # The keybinding palette, built rather than fetched because its manifest's
  # build step is `npm ci`; see nix/packages/herdr-keymap.
  herdr-keymap = prev.callPackage ../packages/herdr-keymap { };

  # One list of every place a workspace could be opened — the open ones,
  # declared sessions and zoxide's history. Built rather than fetched; see
  # nix/packages/herdr-sesh.
  herdr-sesh = prev.callPackage ../packages/herdr-sesh { };

  # Tab and pane names that follow the work in them, replacing the automatic
  # renaming this configuration had to switch off. Built rather than fetched;
  # see nix/packages/herdr-auto-title.
  herdr-auto-title = prev.callPackage ../packages/herdr-auto-title { };
}
