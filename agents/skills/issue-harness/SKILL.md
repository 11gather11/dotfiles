---
name: issue-harness
description: Runs GitHub issues, or the tickets /to-tickets split a spec into, as separate Claude Code workers in herdr or herdr-app terminals, one worktree each, and supervises them through to merge. Use when implementing issues or a spec in parallel, or acting as the harness for workers.
---

You are the harness. Workers implement; you start them, wait on them, triage
what wakes you, land what passes, and bring the rest to the user. Edit nothing
in a worker's worktree yourself.

The scripts split the work by one line: what a rule settles, they do; what
needs reading (a spec question, whose CI failure it is, what goes to the user)
stays with you. They stop and wake you only where their rules run out.

The scripts live in this skill's `scripts/` directory. `nu` is not on PATH, so
run them through Nix, from the repository's main checkout:
`nix shell nixpkgs#nushell --command <skill-dir>/scripts/<script> …`. Each
prints one JSON line last; keep that line when you trim output. Run spawn.nu,
land.nu and spec.nu in the foreground with the Bash tool's `timeout: 600000`
(a script killed by the default timeout leaves no output), and watch.nu,
queue.nu, integrate.nu and review.nu in the background.

Workers run where you do: in herdr panes when you run in the herdr TUI, in
herdr-core terminals (shown in herdr-app) when you run in a herdr-app
terminal. Reach them with `worker.nu`, which goes to the same place, never with
`herdr` or `hc` directly.

## Settings

Machine-local, in `~/.local/state/harness/` (`<repo>` is the checkout's
directory name). Repository rules belong in the repository's CLAUDE.md.

| File                 | Default | Effect                                                                                                                 |
| -------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| `max-workers`        | 4       | Workers running on this machine.                                                                                       |
| `<repo>/max-workers` | machine | Workers running in this repository.                                                                                    |
| `<repo>/brief.md`    | none    | Appended to the worker brief, for what the repository cannot publish (local data paths). Coming last, it can override. |
| `<repo>/no-land`     | absent  | A person merges: land.nu reports the CI verdict instead of merging, and queue.nu does not run.                         |
| `<repo>/check`       | none    | The command a spec's ticket must pass before it joins the integration branch (references/spec.md).                     |

## 0. Set up

At the start of every batch:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/setup.nu
```

It checks what the scripts take for granted and suggests the settings that
fit, changing nothing: bring each `next` that is the user's call (signing,
rulesets, a setting) to them. Its `migrations` are changes to this skill the
repository has not caught up on: do each one's steps, then
`setup.nu migrated <id>`. Done when it returns `ok`.

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
- `--base <branch>`: cut from that branch's latest on origin instead, as for
  stacking on an unlanded PR (`references/landing.md`).

Done when the line has `status: working`. Exit 2 (`stage: capacity`) means the
machine is full: start it after another worker stops. Any other error: fix the
cause in `error`, then run the same command again; it picks up where the last
attempt stopped.

Start a dependent issue only after its dependency has landed, or stack it.
For a spec split into tickets, `spec.nu` works the order out instead: read
[`references/spec.md`](references/spec.md) and start each ticket with
`--spec <spec>`.

## 2. Wait

One background command for every worker that has no PR in the queue:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/watch.nu pg-264 pg-265 pg-270
```

It returns the first worker that is `stopped`, `blocked` or `gone`. A worker
whose turn ended while a background shell or monitor still runs counts as
working. A worker already stopped returns at once, so pass only the ones you
are waiting on. After triage, start it again with the rest. Done when one
watch covers every worker outside the queue, and the queue runs whenever it
holds a PR.

## 3. Triage

Read before you act: `worker.nu read <name> --lines 40`.

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
nix shell nixpkgs#nushell --command <skill-dir>/scripts/worker.nu prompt pg-264 "<text>"
```

Done when the worker is working again, or its case is with the user.

## 4. Land

Before a PR goes in the queue, check what no script can judge:

- The PR body leaves no spec decision open.
- Its "Deferred" section holds only work outside the issue (what the worker
  can still do in this PR goes back to it), each item filed as an issue or a
  comment on the one that owns it: workers cannot write issues.
- What its "for the author to verify" section (marked `<!-- needs-author -->`)
  asks has been verified by the author. `add` refuses such a PR with
  `needs-author` until you pass `--verified`, which you do only once they have.

Then queue it and keep the queue running in the background:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/queue.nu add 312 318
nix shell nixpkgs#nushell --command <skill-dir>/scripts/queue.nu run
```

`add` works while the queue runs. It lands one PR at a time, and returns
`done` when it is empty; otherwise `result` names what stopped it and `next`
what to do. One runner holds a repository's queue: a second `run` returns
`running` with the first one's pid, and a bare `queue.nu` only lists the
queue. How it orders PRs, and the results that need your judgement
(`blocked`, `no-progress`, `flaky`, the limits, `optional-failed`), are in
[`references/landing.md`](references/landing.md); read it the first time the
queue stops on one. `queue.nu run --dry-run` shows what each PR would get,
changing nothing. Landing by hand, `no-land` and stacked PRs are there too.

Done when every queued PR has landed, or its case is with the user.

## 5. Report

Bring to the user, when they arise:

- A spec decision the issue, the documents and the repository's CLAUDE.md do not
  settle.
- Signing, authentication, or anything touching production.
- Main failing on its own.
- An issue given up after three send-backs.

When the batch is done, report each landing in one line with the decisions you
made for it. Then suggest the user run `/mattpocock-skills:retro` here and
sort what it finds: what the repository should change (checks, its CLAUDE.md)
is done there; whatever in this skill or its scripts slowed you down goes in
`~/.local/state/harness/<repo>/retro.md`, which the next revision of the skill
reads. That file stays on this machine: it names private repositories' work.
