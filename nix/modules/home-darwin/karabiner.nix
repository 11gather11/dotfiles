# Karabiner-Elements configuration, built from karabiner/karabiner.ts.
#
# The TypeScript config runs inside a bun2nix derivation: its dependencies come
# from karabiner/bun.nix rather than a node_modules checkout, and the generated
# karabiner.json lives in the store instead of being committed. Only that one
# file is linked — Karabiner writes automatic_backups and assets next to it, so
# ~/.config/karabiner has to stay a plain writable directory.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.xdg) configHome;

  karabinerDir = ../../../karabiner;

  karabinerConfig = pkgs.stdenv.mkDerivation {
    pname = "karabiner-config";
    version = "0-unstable";

    # Named rather than taking the whole directory: Karabiner drops its own
    # backups and assets in there, and every one of them would otherwise become
    # part of the derivation's input hash.
    src = lib.fileset.toSource {
      root = karabinerDir;
      fileset = lib.fileset.unions [
        (karabinerDir + "/karabiner.ts")
        (karabinerDir + "/karabiner.base.json")
        (karabinerDir + "/package.json")
        (karabinerDir + "/bun.lock")
      ];
    };

    nativeBuildInputs = [ pkgs.bun2nix.hook ];

    bunDeps = pkgs.bun2nix.fetchBunDeps {
      bunNix = karabinerDir + "/bun.nix";
    };

    # The only lifecycle script is the postinstall that regenerates bun.nix,
    # which is meaningless inside the sandbox.
    dontRunLifecycleScripts = true;
    # The hook's default phases build and install a compiled executable; this
    # package produces a JSON file instead.
    dontUseBunBuild = true;
    dontUseBunCheck = true;
    dontUseBunInstall = true;

    buildPhase = ''
      runHook preBuild
      # writeToProfile merges the rules into an existing file, so start from the
      # template that carries the profile, the devices and the simple
      # modifications Karabiner owns.
      cp karabiner.base.json karabiner.json
      KARABINER_JSON="$PWD/karabiner.json" bun run karabiner.ts
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 karabiner.json "$out/karabiner.json"
      runHook postInstall
    '';
  };
in
{
  # package.json's postinstall regenerates karabiner/bun.nix with this.
  home.packages = [ pkgs.bun2nix ];

  xdg.configFile."karabiner/karabiner.json".source = "${karabinerConfig}/karabiner.json";

  home.activation.prepareKarabinerConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # ~/.config/karabiner used to be a symlink to the dotfiles checkout, and a
    # linked directory would make home-manager write karabiner.json back into
    # the repository instead of the config directory.
    if [ -L "${configHome}/karabiner" ]; then
      $DRY_RUN_CMD rm "${configHome}/karabiner"
    fi

    # The daemon can enter an inconsistent state if the config changes while it
    # is running, which shows up as a frozen keyboard. Restart it first.
    #
    # Both spellings of the label are matched: this machine registers the agent
    # as karabiner_console_user_server, while newer Karabiner builds register
    # Karabiner-Console-User-Server, and a miss here fails silently.
    label=$(
      /bin/launchctl list \
        | ${lib.getExe pkgs.gnugrep} -o -i -m1 'org\.pqrs\.service\.agent\.karabiner[_-]console[_-]user[_-]server' \
        || true
    )
    if [ -n "$label" ]; then
      echo "Restarting Karabiner console user server before config update..."
      $DRY_RUN_CMD /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$label" 2>/dev/null || true
      sleep 2
    fi
  '';
}
