# Agent skills for Claude Code and Codex
# https://github.com/Kyure-A/agent-skills-nix
#
# Skills are deployed to ~/.agents (standard location, which Codex reads) and
# ~/.config/claude/skills. mattpocock/skills is the exception: Claude Code loads
# it whole as a plugin, and Codex does not get it.
{
  pkgs,
  lib,
  inputs,
  local-skills,
  ...
}:
let
  # External skill repositories are pinned in registry/sources/*.nix rather than
  # as flake inputs: `nix run .#skills-sources-lock` re-resolves them into
  # registry/sources.lock.json, so a skill update no longer moves flake.lock and
  # the update bot no longer opens a PR per skill repository. Each manifest
  # carries its own subdir and idPrefix, which is why the sources below are only
  # the ones that come from a package or from this repository.
  registrySources = inputs.agent-skills.lib.agent-skills.sourcesFromLock {
    manifestsDir = ../../../registry/sources;
    lockFile = ../../../registry/sources.lock.json;
  };
in
{
  programs.agent-skills = {
    enable = true;

    # Pinned sources come from the registry; the rest are paths this
    # configuration already has — a package's own skills, or this repository.
    sources = registrySources // {
      # External: herdr's own agent skill, shipped inside the package source
      herdr = {
        path = pkgs.llm-agents.herdr.src;
        subdir = "skills";
      };
      # External: hunk's own skill, shipped inside the package. It tells an
      # agent to drive a review the user already has open through `hunk
      # session`, rather than opening its own — which is the difference
      # between reviewing together and reviewing twice.
      hunk = {
        path = pkgs.hunk;
        subdir = "share/skills/hunk";
      };
      # External: suiko's own skill, shipped inside the repository the package
      # is built from. It carries the writing workflow the CLI is one step of —
      # decide the reader, write, check, converge — rather than only the flags.
      suiko = {
        path = pkgs.suiko.src;
        subdir = "skills";
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

      # Flat names, because Claude Code reads the directories directly under
      # its skills directory and nothing below them. An id with a `/` in it —
      # which the source's idPrefix produces and the module happily lays out —
      # nests them one level down, where they are simply never found.
      explicit = {
        wrangler = {
          from = "cloudflare";
          path = "wrangler";
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

        # The skill tells an agent to `cargo install suiko` when the CLI is
        # missing, which here would build a second copy beside the one in the
        # store — and fail in any sandbox, having no network.
        suiko = {
          from = "suiko";
          path = "suiko";
          packages = [ pkgs.suiko ];
          transform =
            { original, ... }:
            builtins.replaceStrings
              [ "CLI が見つからない場合（`suiko --version` が失敗する場合）は、次の順で自分で導入する。" ]
              [ "CLI は Nix で入っている。`suiko --version` が失敗する場合は導入を試みず、その旨を報告する。" ]
              original;
        };

        # Registering the source is not installing the skill; each one is named
        # here or it stays in the store. hunk ships exactly one.
        hunk-review = {
          from = "hunk";
          path = "hunk-review";
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

  # mattpocock/skills as the Claude Code plugin it ships as, not as skills
  # picked one by one. A plugin's skills are namespaced — /mattpocock-skills:tdd,
  # /mattpocock-skills:code-review — so they sit beside the local tdd and the
  # built-in /code-review instead of fighting them for the name, and all of them
  # come, which the ask-matt router assumes. Claude Code loads a plugin
  # directory placed under skills/. The repository is the one the registry pins,
  # so skills-sources-lock still moves it.
  xdg.configFile."claude/skills/mattpocock-skills".source = registrySources.mattpocock.path;
}
