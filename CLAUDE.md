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

## Command Privacy and Secret Handling

- Before running any command, make sure the command text, shell history, process list, terminal output, and agent transcript will not contain raw secrets.
- Never put raw secrets, tokens, API keys, passwords, private keys, or credential-bearing environment variable values directly in command strings.
- Use command substitution or existing credential helpers instead, e.g. `$(gh auth token)` or `$GITHUB_TOKEN`, so history and transcripts do not capture the value.
- Do not echo, print, log, summarise, commit, or paste secret values. If a raw secret is accidentally exposed, rotate or revoke it; deleting shell history is not sufficient.

## Project Structure

```
.
├── flake.nix        # Nix entry point
├── nix/modules/     # Nix configuration modules
│   ├── home/        # Cross-platform (home-manager)
│   ├── darwin/      # macOS (nix-darwin)
│   ├── linux/       # Linux
│   └── lib/         # Shared helpers
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

## Git Workflow

- **Main branch**: `main`
- This is a personal dotfiles repo — **committing and pushing directly to `main` is fine**. Do NOT open a pull request unless explicitly asked.
- Use **Conventional Commits** for commit messages.
- Commits are **SSH-signed** (`user.signingkey` / `gpg.format = ssh`, `commit.gpgSign = true`).

## Applying Changes

Editing a Nix file does not change the system until you switch. After modifying
configuration under `nix/modules/`, run `nix run .#switch` to build and activate
it. A git commit hook also runs treefmt and applies the switch automatically.
