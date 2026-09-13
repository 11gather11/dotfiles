---
name: codex-review
description: Run a code review using Codex or a native subagent. Use when the user wants a code review of uncommitted changes, a specific commit, or changes against a base branch.
---

Use the review path that matches the current session:

- Outside Codex: use `codex-review-run`, which runs `codex exec review` and, when it finishes, records the commit it covered. Opening a PR is refused until such a record exists for the commit the PR comes from.
- Inside Codex (Desktop or CLI): delegate the review to a native subagent; do not start a nested Codex process.

## Scope

- A branch: `--base <branch>`, the equivalent of `git diff <branch>...HEAD`. Records HEAD.
- A commit: `--commit <sha>`, the equivalent of `git show <sha>`. Records that commit.
- Uncommitted changes: `--uncommitted`, the equivalent of `git diff HEAD`. Records nothing — there is no commit to open a PR from yet.

Ask when the requested scope is unclear. Return critical findings separately from suggestions, with file and line references.

## Codex CLI

Run it from the worktree whose commit is being reviewed. The record is keyed to that commit, so a review run from the main checkout does not cover a PR opened from a worktree.

```bash
codex-review-run --base main
codex-review-run --commit <sha>
codex-review-run --uncommitted
codex exec review "Focus on error handling and edge cases" </dev/null
```

The positional prompt cannot be combined with a scope flag, and covers no commit. Run `codex exec review --help` when flags are unclear.

A review can take many minutes, so run it in the background and read the result when it ends. `codex-review-run` closes stdin itself; a bare `codex exec` in the background needs `</dev/null`, or it waits for input and never starts.

## Models

Omit `--model`. The configured default applies, and the choice is made and explained in `nix/modules/home/programs/codex.nix`. Pass `--model` only when the user asks for a different one; these are the models available:

!`jq -r '.models[] | "- \(.slug): \(.description)"' "$CODEX_HOME/models_cache.json"`
