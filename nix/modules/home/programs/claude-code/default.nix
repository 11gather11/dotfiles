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

  bun = lib.getExe pkgs.bun-upstream;
  jq = lib.getExe pkgs.jq;
  statuslineScript = ./statusline.ts;

  codexReviewGate = lib.getExe (helpers.codexReviewGate pkgs);

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
    };
    includeCoAuthoredBy = false;
    statusLine = {
      type = "command";
      command = "${bun} ${statuslineScript}";
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

      # `gh pr create` stays shut until codex-review has run over the commit
      # being proposed. The gate's own reasoning lives in the script; what
      # matters here is that both halves are the same binary, because a mark
      # written in one shape and read in another is how the previous one let an
      # unreviewed PR through.
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
      PostToolUse = [
        {
          matcher = "Skill";
          hooks = [
            {
              type = "command";
              command = "${codexReviewGate} mark";
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
    packages = [ pkgs.claude-code ];

    # Set CLAUDE_CONFIG_DIR environment variable (sourced via hm-session-vars.sh in fish)
    sessionVariables = {
      CLAUDE_CONFIG_DIR = claudeConfigDir;
    };

    # Write settings.json as a regular (non-symlink) file so Claude Code can
    # update it (e.g. record permission decisions) without read-only errors.
    activation.writeClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${claudeConfigDir}"
      cp --no-preserve=mode,ownership ${jsonFormat.generate "claude-settings.json" settings} "${claudeConfigDir}/settings.json"
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
