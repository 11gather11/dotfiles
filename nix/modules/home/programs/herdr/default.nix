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

  # Plugin roots to keep registered. Each is a directory laid out the way a
  # plugin repository is, with anything the manifest's [[build]] step would have
  # produced already in place — see nix/packages/herdr-file-viewer.
  plugins = [
    pkgs.herdr-file-viewer
  ];

  herdr = lib.getExe pkgs.llm-agents.herdr;
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

    # `herdr plugin install` fetches a repository and runs its build step at
    # install time, which pins nothing. `link` takes a directory that already
    # exists — including a read-only one in the store — and records it in
    # plugins.json, so the version installed is the version this file names.
    #
    # Registering is idempotent, so every plugin is linked on each activation
    # rather than diffed first. Removal is not: anything registered that this
    # list no longer names is unlinked, which is what makes deleting a line here
    # actually uninstall it, the way homebrew.onActivation.cleanup does.
    activation.linkHerdrPlugins = lib.hm.dag.entryAfter [ "writeHerdrConfig" ] ''
      wanted=""
      ${lib.concatMapStringsSep "\n" (p: ''
        id="$(${pkgs.jq}/bin/jq -r '.result.plugin.plugin_id' <<<"$($DRY_RUN_CMD ${herdr} plugin link ${p} 2>/dev/null)")"
        wanted="$wanted $id"
      '') plugins}

      # A missing or unreadable registry means nothing is registered yet, which
      # is the same as nothing to remove.
      registered="$(${herdr} plugin list --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.result.plugins[]?.plugin_id // empty' || true)"

      for id in $registered; do
        case " $wanted " in
          *" $id "*) ;;
          *)
            echo "herdr: unlinking plugin no longer declared: $id"
            $DRY_RUN_CMD ${herdr} plugin unlink "$id" >/dev/null || true
            ;;
        esac
      done
    '';
  };
}
