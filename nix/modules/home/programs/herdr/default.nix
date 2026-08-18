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

    # The plugin ships its actions and registers them on link; only the key is
    # left to the user, so it belongs here rather than in the package.
    #
    # e for "explorer". Not the f these plugins tend to suggest: f is herdr's
    # own default for zoom and the documentation states no precedence between a
    # command binding and a core one, so taking it would quietly cost a binding
    # without saying which won. herdr's defaults are n, shift+n, shift+d, c, v,
    # -, x, f, r and b; e is unclaimed. The prefix+ form is required — a bare
    # "e", which the configuration reference's own example uses, fails
    # `herdr config check`.
    keys.command = [
      {
        key = "prefix+e";
        type = "plugin_action";
        command = "persiyanov.reviewr.toggle";
        description = "review the agent's diff";
      }
    ];
  };

  # Plugin roots to keep registered. Each is a directory laid out the way a
  # plugin repository is, with anything the manifest's [[build]] step would have
  # produced already in place — see nix/packages/herdr-reviewr.
  plugins = [
    pkgs.herdr-reviewr
    pkgs.herdr-tab-smart-rename
    pkgs.herdr-automatic-rename
    pkgs.herdr-window-title-sync
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
    # herdr-automatic-rename reads its settings from
    # $XDG_CONFIG_HOME/herdr-automatic-rename/config.sh — its own directory, not
    # the per-plugin one under herdr's config. Put here first, it was silently
    # ignored and the tab naming this disables stayed on.
    #
    # NAME_TABS is off deliberately. Naming a tab after its foreground process
    # assumes one tab is one job; every pane in these tabs is an agent, so the
    # names would all read `claude` and flip to whichever pane has focus. The
    # numbering is the half that survives that: it labels each tab with the
    # digit that jumps to it, and does not depend on what is running inside.
    file.".config/herdr-automatic-rename/config.sh".text = ''
      NAME_TABS=0
      AUTO_INDEX=1
    '';

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
