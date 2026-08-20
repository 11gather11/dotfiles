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
    # Codex only runs hooks when this is on, and herdr's integration turns it
    # on by editing config.toml — which this module regenerates on every
    # switch, so the setting lasted until the next one. The hook itself lives
    # in ~/.codex/hooks.json, which nothing here writes, so only this needed
    # declaring. The trust recorded under [hooks.state] is Codex's own state
    # and is not declared: trusting a hook is a decision to make at the prompt.
    features.hooks = true;

    model = "gpt-5.6-sol";
    # auto_review requires the on-request approval policy
    approval_policy = "on-request";
    approvals_reviewer = "auto_review";
    model_reasoning_effort = "medium";
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

    # [hooks.state] is carried across the rewrite. It is not configuration —
    # Codex writes it when a hook is trusted at the prompt, recording the hash
    # of the hook file it agreed to run. Regenerating config.toml erased that,
    # so every switch made Codex ask again.
    #
    # Carried, not declared. Writing the hash from here would mean a hook is
    # trusted because this file says so, and a changed hook would be trusted
    # too — which is the whole thing the mechanism exists to prevent. Preserving
    # what was already answered keeps that intact: if herdr updates the hook,
    # the hash no longer matches and Codex asks again, as it should.
    activation.writeCodexConfig = lib.hm.dag.entryAfter [ "linkCodexXdgDir" ] ''
      mkdir -p "${codexHomeDir}"

      # From the first [hooks.state...] header to the next section that is not
      # one, which is how TOML delimits it — the subsection headers are
      # [hooks.state."<file>:<event>:..."] and sort together.
      state=""
      if [ -f "${codexHomeDir}/config.toml" ]; then
        # Leading whitespace is legal before a TOML header, so the anchors
        # allow it — matching only at column zero swallowed an indented
        # section that followed and carried it across every switch.
        state="$(${pkgs.gawk}/bin/awk '
          /^[[:space:]]*\[hooks\.state/ { keep = 1; print; next }
          /^[[:space:]]*\[/ { keep = 0 }
          keep { print }
        ' "${codexHomeDir}/config.toml")"
      fi

      cp --no-preserve=mode,ownership ${tomlFormat.generate "codex-config" settings} "${codexHomeDir}/config.toml"
      if [ -n "$state" ]; then
        printf '\n%s\n' "$state" >> "${codexHomeDir}/config.toml"
      fi
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
