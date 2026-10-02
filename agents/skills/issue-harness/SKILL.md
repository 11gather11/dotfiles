---
name: issue-harness
description: Runs GitHub issues as separate Claude Code workers in herdr panes, one worktree each, and supervises them through to merge. Use when implementing issues in parallel or acting as the harness for workers.
---

You are the harness. Workers implement; you start them, watch them, answer
what you can, merge what passes, and bring the rest to the user. Edit nothing in
a worker's worktree yourself.

A worker is a full Claude Code session in its own herdr pane rather than a
subagent: the user can open the pane and talk to it, its log stays out of your
context, and it runs with the user's own hooks and skills. Prefer it over a
subagent for any issue that ends in a PR.

For herdr mechanics, run `herdr --skill` or `<command> --help`.

## Start a worker

Run `scripts/spawn.nu` from this skill's directory, in the repository's main
checkout. `nu` is not on PATH, so go through Nix:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/spawn.nu pg-264 issue-264-lint "Implement GitHub issue #264 and open a PR."
```

- Name: a short repository prefix and the issue number, matching
  `[a-z][a-z0-9_-]{0,31}`. The prefix keeps workers from two repositories apart.
- Branch: `issue-<n>-<slug>`.
- Prompt: one line naming the issue, plus anything specific to this issue
  alone. The issue body and the repository's CLAUDE.md carry the rest.

The script creates the worktree, waits for the herdr workspace wt's hook opens,
retries while the new pane is still loading direnv, and starts Claude with
[`references/worker-brief.md`](references/worker-brief.md) appended to its
system prompt. It prints the worker as JSON; done when `status` is `working`.

Machine-local instructions that cannot be committed (local data paths, private
hosts) go in `~/.local/state/harness/<repo>/brief.md`; the script appends it to
the worker brief. Repository rules belong in the repository's CLAUDE.md.

Keep at most four workers running at once. When issues depend on each other,
start a dependent only after its dependency is merged.

## Wait

Wait on each worker with one background command, so each worker wakes you on
its own:

```bash
herdr agent wait pg-264 --timeout 7000000
```

Use the Bash tool's `run_in_background` with a timeout above the wait's own.
Keep one wait per worker; start a new one after you handle each wake-up. When a
worker has opened its PR and stopped, wait on CI instead:

```bash
gh pr checks 312 --watch --fail-fast
```

## On wake-up

Read before you act: `herdr agent get <name>` and `herdr agent read <name>
--lines 40`.

- **blocked**: a permission prompt or an AskUserQuestion. Answer it when the
  issue, the parent spec, the ADRs or CONTEXT.md decide it; otherwise bring it
  to the user. Never approve a permission the user's settings would refuse.
- **idle with `N shells` on screen**: still waiting on a background command.
  Wait again.
- **idle with a PR**: check CI, then merge or send it back.
- **idle without a PR**: read the last turn. A plain-text question gets the same
  treatment as blocked; a stuck worker gets one concrete nudge with
  `herdr agent prompt <name> "<text>" --wait`.
- **wait failed with the agent gone**: the pane closed. Check the worktree for
  uncommitted work before starting over.

Send a worker back with the failing job name and the lines that matter from
`gh run view <run> --log-failed`, and let it decide between a fix and a rerun of
a flaky job. After three send-backs on one issue, stop and report to the user.

## Merge

When `gh pr checks <pr>` passes and the PR body records no open spec decision:

```bash
sha=$(gh pr view 312 --json headRefOid -q .headRefOid)
gh pr merge 312 --squash --match-head-commit "$sha"
git pull --ff-only
wt remove issue-264-lint
```

`--match-head-commit` refuses the merge if the worker pushed after your check.
On a conflict, ask the worker to rebase onto `origin/main` and push. `wt remove`
also closes the herdr workspace and the worker with it.

Gotchas from earlier runs:

- A docs-only PR can skip heavy jobs on purpose; skipped is a pass.
- A commit can get two CI runs, one cancelled. Judge by the run that finished.
- A failed `gh` call is unknown, not open. Retry before starting or restarting
  anything on its result; treating it as open once restarted merged issues.

## Bring to the user

- A spec decision the issue and the documents do not settle.
- Signing, authentication, or anything touching production.
- An issue given up after three send-backs.
- Every merge, in one line each, when the batch is done.
