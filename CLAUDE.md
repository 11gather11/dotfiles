# Dotfiles Repository

11gather11's personal dotfiles, managed via **Nix Flake** (nix-darwin + home-manager).

## Core Commands

```bash
nix run .#switch  # Build and apply the configuration (darwin / home-manager)
nix run .#build   # Build the configuration without applying (test/dry-run)
nix run .#update  # Update flake.lock inputs
nix run .#fmt     # Format the tree with treefmt
```

These wrap `nh`. `programs.nh.flake` points it at this repository, so
`nh darwin switch` and `nh darwin build` work from any directory once the
configuration has been applied once.

## Layout Notes

- Every `.nix` under `nix/modules/` is imported automatically by `import-tree`, so
  adding a module is placing the file — and a half-written or scratch file left
  there becomes part of the configuration. Prefix the filename with `_` to have it
  skipped, or keep it outside `nix/modules/`.
- One class of module per directory (`home/`, `home-darwin/`, `home-linux/`,
  `darwin-system/`). A module in the wrong one is applied to the wrong
  configuration: `home.*` and `programs.*` under `home*/`, anything nix-darwin owns
  under `darwin-system/`. `nix/lib/` is not modules.
- `agents/shared/` fragments are imported by `claude/CLAUDE.md` and concatenated
  into Codex's `AGENTS.md` at switch time. Edit them once; never copy text between
  the two.
- `claude/` is symlinked to `~/.config/claude`, so edits there apply to the running
  Claude Code without a switch.

## Scripting Language Choice

- **Nushell** — the default for any new script. Use the `nushell` skill.
- **Bun Shell or Python** — needs libraries.
- **Bash** — the environment is not ours: Nix build phases, `writeShellApplication`, bootstrap, git hooks.
- **Fish** — interactive config only (`fish/functions/`, abbreviations, completions), never a new script.

## Git Workflow

- This is a personal dotfiles repo — **committing and pushing directly to `main` is fine**. Do NOT open a pull request unless explicitly asked.
- Use **Conventional Commits** for commit messages.

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

Editing a Nix file does not change the system until you switch. The pre-commit
hook runs treefmt and the Nix linters; the post-commit hook runs `nix run .#switch`
when `flake.nix`, `flake.lock`, `nix/`, `agents/` or `codex/AGENTS.md` changed. Run
`nix run .#switch` by hand when you need the change active before committing.
