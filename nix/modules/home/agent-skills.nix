# Agent skills configuration for Claude Code
# https://github.com/Kyure-A/agent-skills-nix
#
# All skills (external and local) are managed here via agent-skills-nix.
# Skills are deployed to ~/.agents (standard location) and ~/.config/claude/skills
{
  pkgs,
  lib,
  inputs,
  local-skills,
  ...
}:
{
  programs.agent-skills = {
    enable = true;

    # Skill sources (from flake inputs)
    sources = {
      # External: ast-grep official skill
      ast-grep = {
        path = inputs.ast-grep-skill;
        subdir = "ast-grep/skills";
      };
      # External: agent-browser skill
      agent-browser = {
        path = inputs.agent-browser-skill;
        subdir = "skills";
      };
      # External: herdr's own agent skill, shipped inside the package source
      herdr = {
        path = pkgs.llm-agents.herdr.src;
        subdir = "skills";
      };
      # External: mattpocock/skills. Two subdirectories hold the current ones;
      # deprecated/ and in-progress/ also exist and are deliberately not read.
      mattpocock-engineering = {
        path = inputs.mattpocock-skills;
        subdir = "skills/engineering";
        # Namespaced, because registering the source at all makes every skill in
        # it visible and this one ships a tdd that collides with the local one.
        idPrefix = "mattpocock";
      };
      mattpocock-productivity = {
        path = inputs.mattpocock-skills;
        subdir = "skills/productivity";
        # Namespaced, because registering the source at all makes every skill in
        # it visible and this one ships a tdd that collides with the local one.
        idPrefix = "mattpocock";
      };
      # Local: skills from this dotfiles repo
      local = {
        path = local-skills;
        subdir = "agents/skills";
      };
    };

    skills = {
      # Enable all local skills
      enableAll = [ "local" ];

      # Skills taken from mattpocock/skills keep that namespace in their id,
      # which the source's idPrefix already produces. It is what lets the
      # upstream tdd sit beside the local one without either being edited,
      # and it keeps where a skill came from readable from its name.
      explicit = {
        # Namespaced rather than renamed. The local tdd keeps the bare name —
        # it carries the loop and detects the project's test runner — and this
        # one sits beside it as what upstream calls "a reference to consult,
        # not a session to run": seams, and the anti-patterns worth naming.
        #
        # A `/` in the id is what the source's idPrefix already produces, so
        # neither side is edited: no rename here, no rewriting of upstream's
        # frontmatter to stop a renamed skill still describing itself as tdd.
        "mattpocock/tdd" = {
          from = "mattpocock-engineering";
          path = "tdd";
        };
        # 計画や設計を執拗に問い詰めて穴を出す
        "mattpocock/grill-me" = {
          from = "mattpocock-productivity";
          path = "grill-me";
        };
        # 同じことを、ユーザーを問い詰める側から
        "mattpocock/grilling" = {
          from = "mattpocock-productivity";
          path = "grilling";
        };
        # grill しながら ADR と用語集を作る
        "mattpocock/grill-with-docs" = {
          from = "mattpocock-engineering";
          path = "grill-with-docs";
        };
        # 難しいバグと性能変化の診断ループ
        "mattpocock/diagnosing-bugs" = {
          from = "mattpocock-engineering";
          path = "diagnosing-bugs";
        };
        # 深いモジュールを設計するための共通語彙
        "mattpocock/codebase-design" = {
          from = "mattpocock-engineering";
          path = "codebase-design";
        };
        # ドメインモデルと用語を磨く
        "mattpocock/domain-modeling" = {
          from = "mattpocock-engineering";
          path = "domain-modeling";
        };
        # 一次情報に当たって Markdown に残す
        "mattpocock/research" = {
          from = "mattpocock-engineering";
          path = "research";
        };
        # 1 セッションに収まらない作業を決定の地図として計画
        "mattpocock/wayfinder" = {
          from = "mattpocock-engineering";
          path = "wayfinder";
        };
        ast-grep = {
          from = "ast-grep";
          path = "ast-grep";
          packages = [ pkgs.ast-grep ];
          transform =
            { original, dependencies }:
            let
              patched =
                builtins.replaceStrings
                  [ "| ast-grep " "ast-grep scan " "ast-grep run " ]
                  [ "| ./ast-grep " "./ast-grep scan " "./ast-grep run " ]
                  original;
            in
            ''
              ${patched}

              ${dependencies}
            '';
        };

        herdr = {
          from = "herdr";
          path = "herdr";
        };

        agent-browser =
          let
            agentBrowserBin = lib.getExe pkgs.llm-agents.agent-browser;
          in
          {
            from = "agent-browser";
            path = "agent-browser";
            packages = [ pkgs.llm-agents.agent-browser ];
            transform =
              { original, ... }:
              builtins.replaceStrings
                [
                  "Bash(npx agent-browser:*), Bash(agent-browser:*)"
                  "./agent-browser"
                ]
                [
                  "Bash(${agentBrowserBin}:*)"
                  agentBrowserBin
                ]
                original;
          };
      };
    };

    # Deploy to standard skills directories
    targets = {
      # Standard ~/.agents/skills directory
      agents = {
        dest = ".agents/skills";
        structure = "link";
      };
      # Claude Code user config
      claude = {
        dest = ".config/claude/skills";
        structure = "link";
      };
    };
  };
}
