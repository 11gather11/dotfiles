{
  pkgs,
  lib,
  config,
  helpers,
  ...
}:
let
  # The app installs from the herdr-app cask (darwin-system/homebrew.nix) and
  # writes settings.json itself — zoom, fonts, theme — so only the keys owned
  # here are merged in, and the rest is left as the app wrote it.
  settings = {
    # On when absent: a daily report of usage counts. Off, as for every other
    # tool here, and turning it off also deletes reports not yet sent.
    telemetry = false;
  };

  mergeConfig = helpers.mergeConfig pkgs;
in
{
  # The engine the app is a client of (`hc`): it runs the terminals and agents
  # and outlives the window. Separate from the herdr TUI this machine already
  # runs. The app finds it on PATH; without it the app offers to curl an
  # installer into ~/.local/bin, outside this configuration.
  home.packages = [ pkgs.llm-agents.herdr-core ];

  home.activation.writeHerdrAppSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${mergeConfig} ${lib.escapeShellArg "${config.xdg.configHome}/herdr-app/settings.json"} ${
      (pkgs.formats.json { }).generate "herdr-app-settings.json" settings
    }
  '';
}
