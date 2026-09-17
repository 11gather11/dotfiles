{
  pkgs,
  lib,
  config,
  helpers,
  ...
}:
let
  mergeConfig = helpers.mergeConfig pkgs;

  # $CODEX_HOME is the canonical directory holding config.toml, AGENTS.md and
  # session state; the XDG path is kept as a symlink to it for compatibility.
  codexHomeDir = "${config.home.homeDirectory}/.codex";
  codexXdgDir = "${config.xdg.configHome}/codex";

  # Global instructions are assembled from the Codex-specific file plus the
  # shared fragments in agents/shared/, which are the single source of truth
  # also imported by claude/CLAUDE.md. Codex has no import mechanism, so the
  # final AGENTS.md is generated at switch time instead of symlinked (edits
  # therefore apply only after nix run .#switch).
  agentsMdText = lib.concatMapStringsSep "\n" builtins.readFile [
    ../../../../codex/AGENTS.md
    ../../../../agents/shared/code-comments.md
    ../../../../agents/shared/command-privacy.md
    ../../../../agents/shared/delegate-work.md
    ../../../../agents/shared/git-staging.md
    ../../../../agents/shared/git-worktrees.md
  ];

  tomlFormat = pkgs.formats.toml { };

  settings = {
    # Codex only runs hooks when this is on, and herdr's integration turns it
    # on by editing config.toml — which this module regenerates on every
    # switch, so the setting lasted until the next one. The hook itself lives
    # in ~/.codex/hooks.json, which nothing here writes, so only this needed
    # declaring. The trust recorded under [hooks.state] is Codex's own state
    # and is not declared: trusting a hook is a decision to make at the prompt.
    # `codex features list` reports goals and multi_agent as already on and
    # memories as off; all three are named here so the set does not change
    # under this configuration when a default does.
    features = {
      hooks = true;
      # Thread objectives, kept in ~/.codex/goals_1.sqlite.
      goals = true;
      # Notes carried between sessions, kept in ~/.codex/memories.
      memories = true;
      # Subagents, which the agents block below configures.
      multi_agent = true;
    };

    agents = {
      max_concurrent_threads_per_session = 100;
      # The same model and depth the lead runs: a subagent reads the code the
      # review is built on, and what it misses the lead never sees. Sol carries
      # the depth that max used to buy on a weaker model, and these run up to a
      # hundred at a time.
      default_subagent_model = "gpt-5.6-sol";
      default_subagent_reasoning_effort = "high";
    };

    # The ChatGPT desktop app, installed as a cask here, reads these.
    desktop = {
      preventSleepWhileRunning = true;
      "show-context-window-usage" = true;
      "hotkey-window-projectless-default-enabled" = false;
      "enabled-reasoning-efforts" = [
        "low"
        "medium"
        "high"
        "xhigh"
        "ultra"
        "max"
      ];
    };

    # Codex here is mostly a reviewer, and a review misses what the model
    # cannot see. Luna is the cheap-and-fast tier, which the previous plan was
    # the reason for; Sol is the workhorse tier above it, and the plan no
    # longer makes that the deciding factor.
    model = "gpt-5.6-sol";
    # auto_review requires the on-request approval policy
    approval_policy = "on-request";
    approvals_reviewer = "auto_review";
    # Measured from this machine's own session logs, reasoning tokens per turn:
    # max 50,282, xhigh about half of that, high 1,953. The depth bought there
    # is what a weaker model needs to keep up; on Sol the base model carries
    # more of it, so the default starts back at high and `/model` raises it for
    # the work that asks.
    model_reasoning_effort = "high";
    # The fast tier buys 1.5x speed for higher usage. What Codex does here runs
    # in the background — reviews take minutes either way — so the usage goes
    # into reasoning above instead. fast_default_opt_out declines Codex's offer
    # to make the fast tier the default again.
    service_tier = "standard";
    notice.fast_default_opt_out = true;
    personality = "pragmatic";
    web_search_request = true;
    project_doc_fallback_filenames = [ "CLAUDE.md" ];
    # Let Codex launch the configured login shell so commands run in the
    # fish-based environment declared by these dotfiles.
    allow_login_shell = true;
    # Source the shell profile so GUI-launched sessions inherit the same env.
    experimental_use_profile = true;

    plugins."github@openai-curated" = {
      enabled = true;
    };

    tui.status_line = [
      "model-with-reasoning"
      "context-used"
      "five-hour-limit"
      "weekly-limit"
    ];
  };
in
{
  home = {
    packages = [ pkgs.llm-agents.codex ];

    sessionVariables = {
      CODEX_HOME = codexHomeDir;
    };

    # Keep the XDG path working as a symlink to the canonical $CODEX_HOME.
    # Refuse to replace a real directory so existing data is never clobbered
    # when the migration has not been performed yet.
    activation.linkCodexXdgDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -e "${codexXdgDir}" ] && [ ! -L "${codexXdgDir}" ]; then
        echo "Refusing to replace non-symlink ${codexXdgDir}" >&2
        exit 1
      fi

      mkdir -p "${codexHomeDir}" "$(dirname "${codexXdgDir}")"
      ln -sfn "${codexHomeDir}" "${codexXdgDir}"
    '';

    # Merged rather than generated whole: Codex writes into this same file. It
    # records [hooks.state] when a hook is trusted at the prompt — the hash of
    # the file it agreed to run — and the desktop app stores its plugin and MCP
    # wiring here too. Rewriting the file erased all of that, and the hook
    # prompt came back on every switch.
    #
    # Those keys are kept, not declared. Writing a hook's hash from here would
    # mean a hook is trusted because this file says so, and a changed hook
    # would be trusted too, which is what the mechanism exists to prevent.
    activation.writeCodexConfig = lib.hm.dag.entryAfter [ "linkCodexXdgDir" ] ''
      $DRY_RUN_CMD ${mergeConfig} "${codexHomeDir}/config.toml" ${tomlFormat.generate "codex-config" settings}
      chmod 644 "${codexHomeDir}/config.toml"
    '';

    file."${codexHomeDir}/AGENTS.md".text = agentsMdText;
  };

  # GUI-launched processes do not read the shell profile, so publish
  # CODEX_HOME to the launchd session at login.
  launchd.agents.codex-home = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/launchctl"
        "setenv"
        "CODEX_HOME"
        codexHomeDir
      ];
      RunAtLoad = true;
    };
  };
}
