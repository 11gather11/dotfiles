---
name: nix-github-rate-limit
description: Prevents and handles GitHub API rate limits with gh-nix. Use when Nix, flakes, nixpkgs commands, or comma may fetch GitHub-backed inputs.
---

Use this skill before Nix commands that may fetch from GitHub.

## Preferred path

Prefix the command with `gh-nix`. It reads the token from authenticated `gh` without putting it in the command, and without exporting it into the process environment where `ps` can read it:

```sh
gh-nix nix flake update
gh-nix nix run github:<owner>/<repo>
gh-nix nix run nixpkgs#<package> -- <args>
gh-nix nix build
gh-nix nix shell nixpkgs#<package> --command <command>
gh-nix , <command>
```

For this repo: `gh-nix nix run .#build`, `gh-nix nix run .#switch`, or `gh-nix nix run .#update`.

Check availability with `command -v gh-nix`. If it is unavailable, use an existing safe token source:

```sh
NIX_CONFIG="access-tokens = github.com=$(gh auth token)" nix <command>
NIX_CONFIG="access-tokens = github.com=$GITHUB_TOKEN" nix <command>
```

Read the token, never paste it: `agents/shared/command-privacy.md` bans the literal form of
exactly this assignment. A substitution keeps the command text safe to store, but the expanded
value still reaches the process environment, which is why `gh-nix` comes first.

Never paste, print, persist, or commit tokens. If `gh-nix` reports that `gh` is unauthenticated, ask the user to run `gh auth login`. Retry a rate-limit failure once with `gh-nix` or the safest available fallback.
