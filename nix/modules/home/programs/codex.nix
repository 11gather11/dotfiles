{
  pkgs,
  lib,
  config,
  ...
}:
let
  codexConfigDir = "${config.xdg.configHome}/codex";

  # Global instructions are assembled from the Codex-specific file plus the
  # shared fragments in agents/shared/, which are the single source of truth
  # also imported by claude/CLAUDE.md. Codex has no import mechanism, so the
  # final AGENTS.md is generated at switch time instead of symlinked (edits
  # therefore apply only after nix run .#switch).
  agentsMdText = lib.concatMapStringsSep "\n" builtins.readFile [
    ../../../../codex/AGENTS.md
    ../../../../agents/shared/code-comments.md
    ../../../../agents/shared/git-worktrees.md
  ];

  tomlFormat = pkgs.formats.toml { };
  bunx = "${pkgs.bun}/bin/bunx";

  settings = {
    model = "gpt-5.5";
    approval_policy = "on-request";
    model_reasoning_effort = "high";
    service_tier = "fast";
    personality = "pragmatic";
    web_search_request = true;
    project_doc_fallback_filenames = [ "CLAUDE.md" ];

    mcp_servers = {
      chrome-devtools = {
        command = bunx;
        enabled = false;
        args = [ "chrome-devtools-mcp@latest" ];
      };
    };

    plugins."github@openai-curated" = {
      enabled = true;
    };
  };
in
{
  home = {
    packages = [ pkgs.llm-agents.codex ];

    sessionVariables = {
      CODEX_HOME = codexConfigDir;
    };

    activation.writeCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${codexConfigDir}"
      cp --no-preserve=mode,ownership ${tomlFormat.generate "codex-config" settings} "${codexConfigDir}/config.toml"
      chmod 644 "${codexConfigDir}/config.toml"
    '';

    file."${codexConfigDir}/AGENTS.md".text = agentsMdText;
  };
}
