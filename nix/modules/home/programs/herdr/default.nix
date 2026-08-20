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

  # herdr-reviewr installs a prebuilt release binary and upstream publishes one
  # for aarch64-darwin only, so naming it anywhere else fails the whole
  # configuration at eval. The other plugins are source trees that link on any
  # platform. Gate the plugin and its binding together — a key bound to a plugin
  # that was never linked is a binding that silently does nothing.
  hasReviewr = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";

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
    keys.command = lib.optionals hasReviewr [
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
    pkgs.herdr-browser
    pkgs.herdr-automatic-rename
    pkgs.herdr-window-title-sync
  ]
  ++ lib.optional hasReviewr pkgs.herdr-reviewr;

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
            "writeHerdrConfig"
          ]
          ''
            ${lib.concatMapStringsSep "\n" (a: ''
              $DRY_RUN_CMD ${herdr} integration install ${a} >/dev/null 2>&1 \
                || echo "herdr: integration install ${a} failed (is it on PATH?)"
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
