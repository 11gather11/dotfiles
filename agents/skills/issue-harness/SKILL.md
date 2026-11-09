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

The scripts split the work by one line: what a rule settles, they do; what
needs reading (a spec question, whose CI failure it is, what goes to the user)
stays with you. They stop and wake you only where their rules run out.

The scripts live in this skill's `scripts/` directory. `nu` is not on PATH, so
run them through Nix, from the repository's main checkout:
`nix shell nixpkgs#nushell --command <skill-dir>/scripts/<script> …`. Each
prints one JSON line last; keep that line when you trim output. Run spawn.nu
and land.nu in the foreground with the Bash tool's `timeout: 600000` (a script
killed by the default timeout leaves no output), and watch.nu and queue.nu in
the background.

## Settings

Machine-local, in `~/.local/state/harness/` (`<repo>` is the checkout's
directory name). Repository rules belong in the repository's CLAUDE.md.

| File                 | Default | Effect                                                                                                                 |
| -------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| `max-workers`        | 4       | Workers running on this machine.                                                                                       |
| `<repo>/max-workers` | machine | Workers running in this repository.                                                                                    |
| `<repo>/brief.md`    | none    | Appended to the worker brief, for what the repository cannot publish (local data paths). Coming last, it can override. |
| `<repo>/no-land`     | absent  | A person merges: land.nu reports the CI verdict instead of merging, and queue.nu does not run.                         |

queue.nu keeps its own state beside them (`queue.json`, `queue-state.json`).

## 0. Set up

At the start of every batch:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/setup.nu
```

It checks what the scripts take for granted (herdr, required checks, squash
merges, no approval needed to merge, the agent signing key, the repository's
CLAUDE.md) and suggests the markers that fit. It changes nothing: bring each
`next` that is the user's call (signing, rulesets, a marker) to them. It also
lists `migrations`, changes to this skill the repository has not caught up
on: carry out each one's steps, then record it with `setup.nu migrated <id>`.

Done when it returns `ok`.

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
- `--base <branch>`: cut the new branch from that branch's latest on origin,
  for a repository whose work branches from elsewhere, or to stack an issue on
  a PR that has not landed (see `references/landing.md`).

Done when the line has `status: working`. Exit 2 (`stage: capacity`) means the
machine is full: start it after another worker stops. Any other error: fix the
cause in `error`, then run the same command again; it picks up where the last
attempt stopped.

Start a dependent issue only after its dependency has landed, or stack it.

## 2. Wait

One background command for every worker that has no PR in the queue:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/watch.nu pg-264 pg-265 pg-270
```

It returns the first worker that is `stopped`, `blocked` or `gone`. A worker
whose turn ended while a background shell or monitor still runs counts as
working. A worker already stopped returns at once, so pass only the ones you
are waiting on. After triage, start it again with the rest.

Done when one watch covers every worker outside the queue, and the queue runs
whenever it holds a PR.

## 3. Triage

Read before you act: `herdr agent read <name> --lines 40`.

- **blocked**: a permission prompt. Answer it or bring it to the user, per
  [`references/triage.md`](references/triage.md).
- **stopped with a question**: workers ask in plain text and end their turn.
  Answer from what decides it, or bring it to the user, per triage.md.
- **stopped with a PR**: read the PR, then queue it (4).
- **stopped otherwise**: read its last turn; a stuck worker gets one concrete
  nudge.
- **gone**: expected after a landing removed its worktree. Otherwise check the
  worktree for uncommitted work before starting it again.

Send every prompt so that only its receipt is awaited:

```bash
herdr agent prompt pg-264 "<text>" --wait --until working --until blocked --timeout 30000
```

Done when the worker is working again, or its case is with the user.

## 4. Land

Before a PR goes in the queue, check what no script can judge:

- The PR body leaves no spec decision open.
- Its "Deferred" section holds only work outside the issue. Anything the
  worker can still do in this PR, such as pulling in what CI generated, goes
  back to the worker instead.
- The rest is filed: workers cannot write issues, so open one per item (or
  comment on the issue that owns it) and link it back.

Then queue it and keep the queue running in the background:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/queue.nu add 312 318
nix shell nixpkgs#nushell --command <skill-dir>/scripts/queue.nu
```

`add` works while the queue runs. The queue lands one PR at a time. Only its
head, the first PR whose worker is free, is asked to merge the base or
brought up to date, because every landing moves the base again. A PR behind
the head lands only when it needs no update. A CI failure goes back to its
worker once per head commit, wherever the PR stands; when the worker answers
that it is not the PR's, the failed jobs are rerun once for that commit. It
returns when:

- `done`: the queue is empty.
- `blocked`, `no-progress`: a worker waits on a prompt, or stopped after an
  ask without pushing or answering that the failure is not the PR's. Read its
  last turn, settle it per triage.md, then run the queue again.
- `flaky`: a failure judged not the PR's failed again after its rerun, or the
  same check was judged so on another PR too. `checks`, `runs` and `detail`
  carry the evidence; handle it as a flake per triage.md.
- `send-back-limit`, `conflict-limit`: bring the issue to the user.
- `optional-failed`: only checks the base does not require failed. Per
  triage.md, let that head land with `queue.nu allow-optional <pr>`, or send
  it back.
- `stalled`: no queued PR can move and no worker is at work, such as a
  stacked PR whose lower PR is not queued. Follow `next`.
- `timeout`: run it again.
- anything else: follow `next`.

Its `landed` holds the PR numbers this run landed; `queue.nu list` has the rest.

`queue.nu --dry-run` shows what each PR would get, changing nothing. To land
one PR by hand, under `no-land`, or to stack PRs, read
[`references/landing.md`](references/landing.md).

Done when every queued PR has landed, or its case is with the user.

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
