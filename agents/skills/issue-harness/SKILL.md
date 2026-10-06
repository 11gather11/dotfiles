---
name: issue-harness
description: Runs GitHub issues as separate Claude Code workers in herdr panes, one worktree each, and supervises them through to merge. Use when implementing issues in parallel or acting as the harness for workers.
---

You are the harness. Workers implement; you start them, wait on them, triage
what wakes you, land what passes, and bring the rest to the user. Edit nothing
in a worker's worktree yourself.

A worker is a full Claude Code session in its own herdr pane rather than a
subagent: the user can open the pane and talk to it, its log stays out of your
context, and it runs with the user's own hooks and skills.

The two scripts live in this skill's `scripts/` directory. `nu` is not on PATH,
so run them through Nix, from the repository's main checkout, with the Bash
tool's `timeout: 600000`: both can wait several minutes, and a script killed by
the default timeout leaves no output. Each prints one JSON line last; keep that
line when you trim output.

## 1. Start

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/spawn.nu pg-264 issue-264-lint "Implement GitHub issue #264 with the tdd skill and open a PR."
```

- Name: a short repository prefix and the issue number (`pg-264`).
- Branch: `issue-<n>-<slug>`.
- Prompt: one line naming the issue and the skill that fits it: `tdd` for
  behaviour to build or change, `diagnosing-bugs` for a bug or a flaky test.
  Add only what is specific to this issue; the issue body and the repository's
  CLAUDE.md carry the rest.
- `--base <branch>`: in a repository whose work branches from a branch other
  than the default, cut the new branch from that branch's latest on origin.

Done when the line has `status: working`. Exit 2 (`stage: capacity`) means the
machine is full: start it after another worker stops working. Any other error:
fix the cause in `error`, then run the same command again; it picks up where
the last attempt stopped.

Start a dependent issue only after its dependency has landed. Machine-local
settings live in `~/.local/state/harness/`:

- `max-workers` (machine-wide) and `<repo>/max-workers`, both default 4.
- `<repo>/brief.md`, appended after the shared worker brief, for what the
  repository cannot publish (local data paths). Coming last, it can override
  the shared brief, such as how the PR closes its issue.
- `<repo>/no-land`, an empty file, for a repository where a person merges:
  Land stops before changing anything and reports instead.

Repository rules belong in the repository's CLAUDE.md.

## 2. Wait

One background command per worker, so each wakes you on its own:

```bash
herdr agent wait pg-264 --timeout 7000000
```

When a worker has opened its PR and stopped, wait on CI instead:
`gh pr checks <pr> --watch --fail-fast`. It exits 1 both on failure and when no
checks exist yet; either way, go to Land, which tells them apart.

Done when every running worker has exactly one wait.

## 3. Triage

Read before you act: `herdr agent get <name>`, `herdr agent read <name> --lines 40`.

- **blocked**: a permission prompt or a question. Answer it or bring it to the
  user, per [`references/triage.md`](references/triage.md).
- **idle with `N shells` on screen**: still waiting on a background command.
  Wait again.
- **idle with a PR**: Land.
- **idle without a PR**: read its last turn. A question gets the blocked
  treatment; a stuck worker gets one concrete nudge.
- **gone**: expected after Land removed its worktree. Otherwise check the
  worktree for uncommitted work before starting it again.

Send every prompt so that only its receipt is awaited, then wait again:

```bash
herdr agent prompt pg-264 "<text>" --wait --until working --until blocked --timeout 30000
```

Done when the worker is working again, or its case is with the user.

## 4. Land

First check what the script cannot judge:

- The PR body leaves no spec decision open.
- Work the PR defers ("moved to #285", "out of scope") is recorded in the issue
  that owns it, or in a new one.

Then:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/land.nu 312 --agent pg-264
```

It checks mergeability, CI, and whether main moved under the PR, then merges
with the head pinned to the commit whose CI it read, pulls main, and removes
the worktree. On anything else it stops with a `result` and a `next`:

- `conflict`: ask the worker to merge `origin/main` into its branch and push.
- `ci-failed`: read `gh run view <run> --log-failed` and decide whose failure it
  is, per [`references/triage.md`](references/triage.md).
- `updated`, `pending`, `no-checks`: CI is (re)starting; wait on it and land
  again.
- `manual-land`: the repository has `no-land`. Its `ci` field carries the CI
  verdict: send a failure back as for `ci-failed`, wait on a pending one, and
  report a pass to the user with the PR URL.
- anything else: follow `next`.

Done when the result is `landed`, or, under `no-land`, when the PR's CI has
passed and the user has its URL. After three send-backs on one issue, stop and
bring it to the user.

## 5. Report

Bring to the user, when they arise:

- A spec decision the issue, the documents and the repository's CLAUDE.md do not
  settle.
- Signing, authentication, or anything touching production.
- Main failing on its own.
- An issue given up after three send-backs.

When the batch is done, report each landing in one line with the decisions you
made for it, and append to `~/.local/state/harness/<repo>/retro.md` whatever
in this skill or its scripts slowed you down, so the next revision has it.
