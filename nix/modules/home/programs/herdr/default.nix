# docs
# https://herdr.dev/docs/configuration/
#
# Validate after changing: `herdr config check`

{
  pkgs,
  lib,
  config,
  ...
}:
let
  herdrConfigDir = "${config.xdg.configHome}/herdr";

  tomlFormat = pkgs.formats.toml { };

  settings = {
    onboarding = false;

    ui = {
      agent_panel_sort = "spaces";
    };
  };
in
{
  home = {
    packages = [ pkgs.llm-agents.herdr ];

    # Written as a regular file rather than a symlink: herdr edits config.toml
    # itself from the Settings TUI, and the rest of this directory is runtime
    # state it owns outright (session.json, sockets, logs, plugins.json — the
    # last written by `herdr plugin install`). Only this one file is managed.
    activation.writeHerdrConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${herdrConfigDir}"
      cp --no-preserve=mode,ownership ${tomlFormat.generate "herdr-config.toml" settings} "${herdrConfigDir}/config.toml"
      chmod 644 "${herdrConfigDir}/config.toml"
    '';
  };
}
