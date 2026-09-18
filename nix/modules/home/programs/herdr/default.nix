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

      # Which agent is in which pane, written on the pane's own border. Tab
      # names cannot carry it — several agents share a tab here, which is the
      # reason naming a tab after its foreground process was turned off above.
      # The border is per pane, so it says what the tab cannot.
      show_agent_labels_on_pane_borders = true;
    };

    # Images drawn into a pane travel over the Kitty graphics protocol, which
    # herdr keeps behind this flag and Ghostty speaks. snacks' image viewer is
    # what needs it here — a pane without it shows a blank where the picture is.
    experimental.kitty_graphics = true;

    # Space is Neovim's leader here, so ctrl+space puts herdr beside it: one
    # thumb key for both, told apart by whether ctrl is held. The default
    # ctrl+b also shadowed copy mode's own page-up.
    #
    # The cost is on the Neovim side, which never sees ctrl+space again: blink's
    # manual completion trigger and LazyVim's syntax-node selection. Completion
    # opens on its own anyway. macOS claims the chord for switching input
    # sources, which nix/modules/darwin-system/activation.nix turns off.
    keys.prefix = "ctrl+space";

    # Typing Japanese, the key after the prefix reaches the input method first
    # and `f` becomes a kana instead of a herdr command. This switches to an
    # ASCII source for the length of prefix mode only.
    experimental.switch_ascii_input_source_in_prefix = true;

    # A plugin action is reachable without a binding — `herdr plugin action
    # invoke <id>` — but reaching for a hint overlay through a command line is
    # the mouse round trip it exists to remove. Both keys are free in 0.9.1;
    # `herdr config check` rejects a binding that collides.
    keys.command = [
      {
        key = "prefix+f";
        type = "plugin_action";
        command = "rmarganti.herdr-pluck.pluck";
        description = "pluck visible token";
      }
      {
        key = "prefix+shift+f";
        type = "plugin_action";
        command = "rmarganti.herdr-pluck.open-url";
        description = "open visible URL";
      }
    ];
  };

  # Plugin roots to keep registered. Each is a directory laid out the way a
  # plugin repository is, with anything the manifest's [[build]] step would have
  # produced already in place.
  plugins = [
    pkgs.herdr-automatic-rename
    pkgs.herdr-window-title-sync
    pkgs.herdr-hunk-diff
    pkgs.herdr-pluck
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

    # Written as a regular file rather than a symlink, because herdr opens
    # config.toml for writing when the Settings TUI applies a change — a
    # symlink into the store fails there. It is still overwritten on every
    # switch, so a setting changed in that TUI lasts until the next one and
    # then goes. Anything worth keeping belongs in this file; the TUI is for
    # finding out what a setting does.
    #
    # The rest of the directory is runtime state herdr owns outright —
    # session.json, sockets, logs, plugins.json — and none of it is touched.
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

    # herdr-pluck's built-in patterns already cover URLs, paths, git SHAs, hex
    # literals, UUIDs and IPs. A Nix SRI hash matches none of them — it is the
    # one token here that is routinely copied out of a build failure by hand,
    # which is the whole reason this plugin is installed.
    #
    # Unlike herdr's own config.toml this is a symlink: herdr never writes a
    # plugin's config, the plugin reads it, and nothing here has a TUI that
    # would need to open it for writing.
    file.".config/herdr/plugins/config/rmarganti.herdr-pluck/config.toml".source =
      tomlFormat.generate "herdr-pluck-config.toml"
        {
          patterns = [
            {
              name = "nix-sri-hash";
              regex = "sha256-[0-9a-zA-Z+/]{43}=";
              priority = 25;
            }
          ];
        };

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
            # herdr finds each agent's config directory the way the agent does,
            # through these variables, and activation does not run with the
            # session's environment. Without them the Claude integration went to
            # ~/.claude, which nothing here reads, while the copy Claude Code
            # actually runs stayed at an old version.
            export CLAUDE_CONFIG_DIR=${lib.escapeShellArg config.home.sessionVariables.CLAUDE_CONFIG_DIR}
            export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}

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

      # A switch installs a new herdr binary but cannot touch the server already
      # running, which keeps the binary it started with until it is stopped.
      # When the protocol changed, installHerdrIntegrations above already fails
      # loudly. When it did not, every command still succeeds and nothing says
      # the new version is not the one running — a server stayed on 0.9.0 for
      # three and a half days of 0.9.1 switches that way, and the fix for the
      # lag in graphics panes that 0.9.1 carried never reached it.
      #
      # herdr reports both conditions itself. Only a warning, never a restart:
      # stopping the server ends every process in every pane, and this switch is
      # often running inside one.
      warnStaleHerdrServer = lib.hm.dag.entryAfter [ "linkHerdrPlugins" ] ''
        if status="$(${herdr} status --json 2>/dev/null)"; then
          stale="$(${pkgs.jq}/bin/jq -r '.update.server_binary_stale == true or .update.restart_needed == true' <<<"$status")"
          if [ "$stale" = true ]; then
            running="$(${pkgs.jq}/bin/jq -r '.server.version // "unknown"' <<<"$status")"
            echo "herdr: the running server is $running, but this switch installed ${pkgs.llm-agents.herdr.version}." >&2
            echo "herdr: the new version is not in effect until the server restarts: herdr server stop && herdr" >&2
          fi
        fi
      '';
    };
  };
}
