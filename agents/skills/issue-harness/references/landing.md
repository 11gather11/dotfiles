# Landing without the queue, and stacked PRs

## By hand

To land a single PR by hand, or under `no-land`, run land.nu:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/land.nu 312 --agent pg-264
```

It checks the PR, its CI and whether the base moved under it, merges with the
head pinned to the commit whose CI it read, pulls, and removes the worktree.
After `updated` (it merged the base into the PR), wait for the new CI: lines
that merge cleanly can still disagree. Under `no-land` it returns
`manual-land` with the CI verdict: send a failure back, wait on a pending one,
and give the user the PR URL once it passes. It never lands a PR from a fork.
Run on a PR a person already merged (under `no-land`, or `gh pr merge
--auto`), it returns `merged` and removes the worktree and worker the PR left;
the queue does the same for a queued PR merged that way.

After three send-backs on one issue, stop and bring it to the user.

GitHub's merge queue is not used: it is not available to every repository
this runs in.

## Stacked PRs

Stack an issue on an unlanded PR with `spawn.nu --base <its branch>`. The
queue passes a stacked PR over until the PR under it lands; its CI still runs
on every push meanwhile. When the lower PR lands, GitHub retargets the upper
one to the default branch if the repository deletes merged branches;
otherwise run `gh pr edit <upper> --base <default>`. From then on the queue
treats it as any other PR, asking for a merge of the base when it conflicts.

## The queue

Its state is in `~/.local/state/harness/<repo>/` (`queue.json`, `queue-state.json`).

The queue lands one PR at a time. Only its
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
- `api-error`: a worker stopped on an error only the user can clear
  (`/login`, a usage limit). Bring it to them, then run the queue again.
- `no-runner`: the head's CI jobs have sat queued for 30 minutes with none
  started. Check the repository's runners (a self-hosted one offline, Actions
  minutes or billing spent) before running the queue again.
- `busy`: a worker ended its turn 30 minutes ago with a background shell or
  monitor still running, so the queue has been passing its PR over. Read it;
  if what runs is left over (a CI watch after the PR opened), ask it to stop
  that.
- `running`: another runner holds the queue. With `stale: true` it started
  before the skill was updated and runs the old scripts: stop it and run the
  queue again.
- `timeout`: run it again, and report what `landed` holds.
- anything else: follow `next`.

Its `landed` holds the PR numbers this run landed. `queue.nu list` shows the
queue, its runner and the last few landings; `--all` every ask and landing.
