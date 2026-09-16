{
  pkgs,
  lib,
  config,
  dotfilesDir,
  helpers,
  ...
}:
let
  claudeConfigDir = "${config.xdg.configHome}/claude";
  claudeDotfilesDir = "${dotfilesDir}/claude";

  jq = lib.getExe pkgs.jq;
  nu = lib.getExe pkgs.nushell;
  statuslineScript = ./statusline.nu;

  codexReviewGate = lib.getExe (helpers.codexReviewGate pkgs);
  mergeConfig = helpers.mergeConfig pkgs;

  # The name agents type to review. It is the same binary as the gate, so the
  # record a review writes and the record the gate reads cannot drift apart.
  codexReviewRun = pkgs.writeShellScriptBin "codex-review-run" ''
    exec ${codexReviewGate} run "$@"
  '';

  jsonFormat = pkgs.formats.json { };

  baseSettings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    cleanupPeriodDays = 876000;
    env = {
      ENABLE_BACKGROUND_TASKS = "1";
      FORCE_AUTO_BACKGROUND_TASKS = "1";
      DISABLE_MICROCOMPACT = "1";

      DISABLE_INTERLEAVED_THINKING = "1";
      DISABLE_ERROR_REPORTING = "1";

      CLAUDE_CODE_NO_FLICKER = "1";

      # Subagents do the searching and reading that the answers are built on,
      # and a cheaper model there is paid for in what the lead has to redo.
      CLAUDE_CODE_SUBAGENT_MODEL = "opus";
    };
    includeCoAuthoredBy = false;
    statusLine = {
      type = "command";
      # --stdin hands Claude Code's JSON to main as $in. --no-config-file,
      # since this runs on every statusline refresh and uses nothing from
      # the interactive config.
      command = "${nu} --no-config-file --stdin ${statuslineScript}";
    };
    model = "opus";
    alwaysThinkingEnabled = true;
    autoMemoryEnabled = false;
    useAutoModeDuringPlan = true;
    effortLevel = "high";
    skipAutoPermissionPrompt = true;
    skipDangerousModePermissionPrompt = true;
    hooks = {
      # herdr's agent integration. The script is installed and versioned by
      # `herdr integration install claude` — see the herdr module — but the
      # registration belongs here, because this file is regenerated on every
      # switch and anything herdr appends to it is lost at the next one. That
      # is not hypothetical: the hook was added, a switch overwrote it, and
      # `herdr integration status` went on reporting "current" because it only
      # checks that the script exists, not that anything calls it.
      SessionStart = [
        {
          matcher = "*";
          hooks = [
            {
              type = "command";
              command = "bash '${claudeConfigDir}/hooks/herdr-agent-state.sh' session";
              timeout = 10;
            }
          ];
        }
      ];

      # `gh pr create` stays shut until a Codex review has run to completion
      # over the commit being proposed. The gate's own reasoning lives in the
      # script. The record is written by codex-review-run when the review ends,
      # not by a hook: the Skill tool returns when the skill loads, so a hook on
      # it marked the commit before anything had been read.
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${codexReviewGate} check";
            }
          ];
        }
      ];
    };
  };

  darwinSettings = lib.optionalAttrs pkgs.stdenv.isDarwin {
    permissions = {
      defaultMode = "auto";
      allow = [
        "Bash(jq -r:*)"
        "Bash(codex exec:*)"
        "Bash(codex-review-run:*)"
        "Bash(codex debug:*)"
      ];
    };
  };

  mergeSettings =
    base: override:
    let
      baseHooks = base.hooks or { };
      overrideHooks = override.hooks or { };
      allHookKeys = lib.unique (lib.attrNames baseHooks ++ lib.attrNames overrideHooks);
      mergedHooks = lib.genAttrs allHookKeys (
        key: (baseHooks.${key} or [ ]) ++ (overrideHooks.${key} or [ ])
      );
    in
    base // override // { hooks = mergedHooks; };

  settings = mergeSettings baseSettings darwinSettings;
in
{
  home = {
    # Claude Code package from overlay
    packages = [
      pkgs.claude-code
      codexReviewRun
    ];

    # Set CLAUDE_CONFIG_DIR environment variable (sourced via hm-session-vars.sh in fish)
    sessionVariables = {
      CLAUDE_CONFIG_DIR = claudeConfigDir;
    };

    # Merged rather than copied, and written as a regular file rather than a
    # store symlink, because Claude Code writes into settings.json itself —
    # `/config` stores UI preferences there, `/permissions` records decisions.
    # Copying the generated file over it dropped all of that on every switch.
    # The keys declared above still win; everything else is left alone.
    activation.writeClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${mergeConfig} "${claudeConfigDir}/settings.json" ${jsonFormat.generate "claude-settings.json" settings}
      chmod 644 "${claudeConfigDir}/settings.json"
    '';

    # Validate Claude Code settings.json after generation
    activation.validateClaudeSettings = lib.hm.dag.entryAfter [ "writeClaudeSettings" ] ''
      SETTINGS_FILE="${claudeConfigDir}/settings.json"
      SCHEMA_URL=$(${jq} -r '.["$schema"]' "$SETTINGS_FILE")

      echo "🔍 Validating Claude Code settings.json..."
      if ${lib.getExe pkgs.check-jsonschema} --schemafile "$SCHEMA_URL" "$SETTINGS_FILE" 2>&1; then
        echo "✅ Claude Code settings.json validation passed"
      else
        echo "⚠️  Claude Code settings.json validation failed (non-blocking, schema may be outdated)" >&2
      fi
    '';
  };

  # Symlink directories and files to ~/.config/claude/
  # Note: settings.json is written via activation script above (writable file)
  # Note: All skills (external and local) are managed by agent-skills module
  xdg.configFile = {
    "claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/CLAUDE.md";
    # Shared instruction fragments imported by CLAUDE.md via @~/.config/claude/shared/*.md
    "claude/shared".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/agents/shared";
    "claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/commands";
    "claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/agents";
    "claude/output-styles".source =
      config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/output-styles";
    "claude/rules".source = config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/rules";
  };
}
