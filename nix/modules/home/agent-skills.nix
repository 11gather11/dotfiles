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
let
  # mattpocock/skills is two directories of same-shaped entries, so name them
  # once rather than writing `from` and `path` out for each.
  mattpocockSelect =
    groups:
    lib.concatMapAttrs (
      group: names:
      lib.genAttrs names (name: {
        from = "mattpocock-${group}";
        path = name;
      })
    ) groups;
in
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
      # External: hunk's own skill, shipped inside the package. It tells an
      # agent to drive a review the user already has open through `hunk
      # session`, rather than opening its own — which is the difference
      # between reviewing together and reviewing twice.
      hunk = {
        path = pkgs.hunk;
        subdir = "share/skills/hunk";
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
      # External: cloudflare/skills. Thirteen of them; wrangler is the one
      # taken, since Workers work here goes through that CLI.
      cloudflare = {
        path = inputs.cloudflare-skills;
        subdir = "skills";
      };
      # External: Orca's own skills, eight of them shipped inside the app's
      # repository. Registering the source makes all eight visible, so the one
      # that is wanted is named in `explicit` below rather than enabled here.
      orca = {
        path = inputs.orca-skills;
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
        # Selected from mattpocock/skills. Names only: each is a directory in
        # the source and installs under the same name, so the interesting part
        # is which ones and not how.
        #
        # Flat, because Claude Code reads the directories directly under its
        # skills directory and nothing below them. The source's idPrefix
        # produces `/`-separated ids, and the module lays those out as nested
        # directories, where nothing ever finds them.
        #
        # tdd is the exception: the local one keeps the bare name because it is
        # the one to run — it carries the loop and detects the project's test
        # runner — and upstream's installs alongside as what its own text calls
        # "a reference to consult, not a session to run".
      }
      // mattpocockSelect {
        engineering = [
          "grill-with-docs"
          "diagnosing-bugs"
          "codebase-design"
          "domain-modeling"
          "research"
          "wayfinder"
        ];
        productivity = [
          "grill-me"
          "grilling"
        ];
      }
      // {
        wrangler = {
          from = "cloudflare";
          path = "wrangler";
        };

        # Two of the eight Orca ships. The Linear pair, both emulators,
        # computer-use and per-workspace-env are left behind: every skill's
        # description sits in the context window whether or not it is ever
        # used, and none of those have a use here.
        #
        # orca-cli drives worktrees, terminals and the embedded browser through
        # the `orca` CLI, and says to prefer that over raw `git worktree` and
        # ad hoc PTYs whenever the task touches state Orca already owns.
        orca-cli = {
          from = "orca";
          path = "orca-cli";
        };
        # orchestration is the other half: a coordinator dispatching workers,
        # with threaded messages, blocking ask/reply, task DAGs and decision
        # gates. It draws the line at handoffs — passing ownership on is
        # orca-cli's, and this one is for work that stays supervised.
        orchestration = {
          from = "orca";
          path = "orchestration";
        };

        # The one that cannot keep upstream's name: the local tdd holds it.
        mattpocock-tdd = {
          from = "mattpocock-engineering";
          path = "tdd";
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
}
