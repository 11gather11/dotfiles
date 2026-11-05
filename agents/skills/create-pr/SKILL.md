---
name: create-pr
description: Branches, commits, pushes, and opens a pull request. Use when the user asks to create, open, or file a PR.
---

# Create PR

A PR is one reviewable responsibility and may hold several commits. Split
independent work into separate PRs; stack only work that depends on another PR.

## Workflow

1. Read `git status --short`, `git branch --show-current`, and `git diff --stat`.
   Work on the user’s named branch, creating or switching to it as needed.
   Otherwise create a `feature/`, `fix/`, or `chore/` branch when on `main`.
2. Leave out unrelated changes, temporary files, secrets, and debug edits, then
   commit with the `commit` skill.
3. Title: follow the repository's convention (check recent merged PRs; default
   to a Conventional Commit type). State why the change matters, not the
   mechanism:
   - ❌ `perf(server): negotiate permessage-deflate on the websocket`
   - ✅ `perf(server): cut websocket frame size by 70%+ with gzipping`
4. Body, in proportion to the change: what changed, the root cause, and why this
   fix. Add a Testing section only for tests actually run. Pass multi-line
   bodies with `--body-file -`.
5. For a visible change, attach real screenshots or short videos with
   `gh pr create --attach` (see `gh pr create --help`); never invent media.
6. Publish: `git push -u origin <branch>` and `gh pr create --base <target-branch>`,
   using the requested target, or the repository default when unspecified.
7. Report the PR URL. Don't call it ready until checks and review feedback have
   been looked at.
