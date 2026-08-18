# Dotfiles Repository

11gather11's personal dotfiles, managed via **Nix Flake** (nix-darwin + home-manager).

## Quick Reference

See @README.md for full documentation.

## Core Commands

```bash
nix run .#switch  # Build and apply the configuration (darwin / home-manager)
nix run .#build   # Build the configuration without applying (test/dry-run)
nix run .#update  # Update flake.lock inputs
nix run .#fmt     # Format the tree with treefmt
```

These wrap `nh`, which is also usable directly once the configuration has been
applied once — `programs.nh.flake` points it at this repository, so it works
from any directory:

```bash
nh darwin switch   # same as nix run .#switch
nh darwin build    # same as nix run .#build
nh darwin switch --ask --no-nom
```

## Command Privacy and Secret Handling

- Before running any command, make sure the command text, shell history, process list, terminal output, and agent transcript will not contain raw secrets.
- Never put raw secrets, tokens, API keys, passwords, private keys, or credential-bearing environment variable values directly in command strings.
- Use command substitution or existing credential helpers instead, e.g. `$(gh auth token)` or `$GITHUB_TOKEN`, so history and transcripts do not capture the value.
- Do not echo, print, log, summarise, commit, or paste secret values. If a raw secret is accidentally exposed, rotate or revoke it; deleting shell history is not sufficient.

## Project Structure

```
.
├── flake.nix        # Nix entry point
├── nix/
│   ├── flake/       # flake-parts modules (apps, treefmt, configurations, …)
│   ├── lib/         # mk-system.nix and helpers — not modules
│   └── modules/     # auto-imported by import-tree; one class per directory
│       ├── home/          # home-manager, both platforms
│       ├── home-darwin/   # home-manager, macOS only
│       ├── home-linux/    # home-manager, Linux only
│       └── darwin-system/ # nix-darwin system modules（core / defaults / homebrew …）
├── fish/            # Fish shell config
├── bash/            # Bash config
├── zsh/             # Zsh config
├── nvim/            # Neovim config (Lua, Lazy.nvim)
├── karabiner/       # Karabiner-Elements config (TypeScript)
├── agents/skills/   # Shared AI agent skills (Claude, Codex)
├── claude/          # Claude Code config (user memory, rules)
├── codex/           # Codex config
└── .claude/         # Path-specific rules & local skills
```

## Scripting Language Choice

- **Nushell** — the default for any new script. Use the `nushell` skill.
- **Bun Shell or Python** — needs libraries.
- **Bash** — the environment is not ours: Nix build phases, `writeShellApplication`, bootstrap, git hooks.
- **Fish** — interactive config only (`fish/functions/`, abbreviations, completions), never a new script.

## Git Workflow

- **Main branch**: `main`
- This is a personal dotfiles repo — **committing and pushing directly to `main` is fine**. Do NOT open a pull request unless explicitly asked.
- Use **Conventional Commits** for commit messages.
- Commits are **SSH-signed** (`user.signingkey` / `gpg.format = ssh`, `commit.gpgSign = true`).

### This repository is public

Everything committed here is published, and that includes commit messages.
Employment is not the subject of this repository, so keep it out of them.

- Do not name employers, clients, internal repositories, organisations or work
  account names in commit messages, comments or file contents. Write "the work
  checkout", "the client organisation", "the work account" instead. Paths are
  fine as `github.com/<org>/<repo>`.
- The same goes for anything describing work: internal service names, ticket
  IDs, customer-facing project names.
- Work configuration deliberately lives outside this repository —
  `~/.gitconfig.work` is untracked and holds the work identity, and the tooling
  here reads it by path. **Do not make any of it declarative.** In a public
  repository, declaring a value and publishing it are the same act.
- Personal identity is already public and needs no such care.

This was learned the hard way: commit messages written for reproducibility named
a client, its repositories and the work account, and they were pushed before
anyone noticed. Rewriting published history only half works, so the rule is to
not write it in the first place. Explanations lose nothing by being generic —
ten commit messages were rewritten without losing any of their reasoning.

## Applying Changes

Editing a Nix file does not change the system until you switch. After modifying
configuration under `nix/modules/`, run `nix run .#switch` to build and activate
it. A git commit hook also runs treefmt and applies the switch automatically.
