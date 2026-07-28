{
  pkgs,
  lib,
  config,
  ...
}:
let
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
    ../../../../agents/shared/git-worktrees.md
  ];

  tomlFormat = pkgs.formats.toml { };

  settings = {
    model = "gpt-5.6-sol";
    # auto_review requires the on-request approval policy
    approval_policy = "on-request";
    approvals_reviewer = "auto_review";
    model_reasoning_effort = "high";
    service_tier = "fast";
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

    activation.writeCodexConfig = lib.hm.dag.entryAfter [ "linkCodexXdgDir" ] ''
      mkdir -p "${codexHomeDir}"
      cp --no-preserve=mode,ownership ${tomlFormat.generate "codex-config" settings} "${codexHomeDir}/config.toml"
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
