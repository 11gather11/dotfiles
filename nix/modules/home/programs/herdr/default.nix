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

      # herdr asks every new tab for a name. With automatic naming on there is
      # nothing for it to do, and worse: a name typed into that prompt counts as
      # a hand rename, which opts the tab out of automatic naming for good.
      prompt_new_tab_name = false;
    };

    # herdr-browser draws Chromium into a pane through the Kitty graphics
    # protocol, which herdr keeps behind this flag. Ghostty speaks it.
    experimental.kitty_graphics = true;

  };

  # Plugin roots to keep registered. Each is a directory laid out the way a
  # plugin repository is, with anything the manifest's [[build]] step would have
  # produced already in place.
  plugins = [
    pkgs.herdr-browser
    pkgs.herdr-automatic-rename
    pkgs.herdr-window-title-sync
    pkgs.herdr-hunk-diff
  ];

  # Agents whose official integration should be installed. Without one, herdr
  # reads an agent's state from what its TUI draws, and a pane restored after a
  # server restart comes back as a plain shell rather than the conversation —
  # which is what happened to three work panes when herdr was last restarted.
  #
  # Only agents actually installed here: `herdr integration` offers seventeen.
  integrations = [
    "claude"
    "codex"
    "grok"
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
    # Naming a tab after its foreground process assumes one tab is one job,
    # which these tabs are not — several agents share one, so the name follows
    # whichever pane has focus. It is on regardless: the alternative was an
    # LLM naming them from the conversation, and that wanted a paid API key
    # rather than the subscriptions already here, so a name that moves beats no
    # name at all. The numbering is unaffected either way.
    file.".config/herdr-automatic-rename/config.sh".text = ''
      NAME_TABS=1
      AUTO_INDEX=1
    '';

    activation = {
      writeHerdrConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
      # After the agents' own settings are written, not before: installing an
      # integration appends a hook to files this configuration also generates —
      # claude's settings.json is copied fresh on every switch — so running this
      # first would have it overwritten moments later. Installing is idempotent
      # and reports "current" when nothing changed.
      #
      # This restores the integration when the configuration changes, not on
      # every switch: a switch that builds an identical closure does not re-run
      # home-manager's activation at all. Verified by deleting the hook and
      # switching — it came back only once something else had changed. So this
      # keeps the integration declared and repairs it alongside real changes; it
      # is not a guard against something deleting the hook in between.
      installHerdrIntegrations =
        lib.hm.dag.entryAfter
          [
            "writeClaudeSettings"
            # Codex's config.toml is regenerated too, and the integration writes
            # into it — without this the install ran five hundred lines before
            # the file that overwrites it, in the same switch.
            "writeCodexConfig"
            "writeHerdrConfig"
          ]
          ''
            ${lib.concatMapStringsSep "\n" (a: ''
              # Fail the activation. Swallowing this let a switch report success
              # while the declared integration was not installed — and there is
              # a routine way to reach it: Nix updates the CLI while the server
              # keeps running the version it started with, and every herdr
              # command then fails on the protocol mismatch.
              if ! out="$($DRY_RUN_CMD ${herdr} integration install ${a} 2>&1)"; then
                echo "herdr: integration install ${a} failed:" >&2
                echo "$out" >&2
                case "$out" in
                  *protocol*)
                    echo "herdr: the CLI is newer than the running server; stop it and switch again." >&2
                    ;;
                esac
                exit 1
              fi
            '') integrations}
          '';

      linkHerdrPlugins = lib.hm.dag.entryAfter [ "writeHerdrConfig" ] ''
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
  };
}
