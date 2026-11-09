# A spec on one integration branch

For a spec issue that `/to-tickets` split into sub-issues with blocked-by
links. Each ticket gets a worker as usual, but no ticket is pushed or gets a
PR: each merges into the spec's local integration branch `spec-<n>` after
the repository's integration check passes, and the spec reaches the base as
one PR, so CI runs once for the whole spec.

The integration check is the command in `~/.local/state/harness/<repo>/check`
(`just check && just test-core`, say): whatever can run on this machine.
What only CI runs (e2e, screenshots) is first seen on the spec's PR, so a
failure there is traced back to a ticket by its merge (step 8).

Run `spec.nu` in the foreground; `integrate.nu` and `review.nu` in the
background.

## 1. Start the spec

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/spec.nu start 412
```

Creates `spec-412` from the base's latest on origin, in its own worktree, and
returns `ready`: the tickets that can start. `spec.nu frontier 412` gives the
same at any time.

## 2. Start a worker per ready ticket

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/spawn.nu kn-415 issue-415-export "Implement ticket #415 of spec #412 with the tdd skill." --spec 412
```

`--spec` cuts the branch from the local `spec-412` and briefs the worker not
to push, to merge `spec-412` when asked, and to end with `DONE`. Machine
capacity applies as for any worker.

## 3. Integrate each ticket that ends with DONE

Wait on the workers with watch.nu and triage as usual. When one stops with
`DONE`:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/integrate.nu 412 issue-415-export
```

One at a time: every merge moves `spec-412`.

- `integrated`: merged, worktree removed (the branch stays until the spec
  lands). Start the tickets in `ready`.
- `behind`, `dirty`, `check-failed`: already sent to the worker. Wait on it,
  and integrate again when it ends with `DONE`.
- `working`, `busy`, `blocked`: the worker has not stopped; wait.
- `head-moved`: the branch moved during the check; run it again.

Repeat 2 and 3 until `done`. `stuck` means no ticket can start and none is
under way: a cycle, or a blocker outside the spec still open. Bring it to the
user.

## 4. Review the spec

In the integration worktree, have Codex review it as Matt Pocock's
code-review does, on the spec and every ticket:

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/review.nu --base main 412 415 416 417
```

Read the report; choose what to fix. A spec question goes to the user. For
each fix, start a worker with `--spec 412` on a branch `spec-412-fix-<slug>`,
naming the findings it fixes, and integrate it as in 3.

## 5. Finish

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/spec.nu finish 412
```

Merges the base's latest into `spec-412` and runs the check there.
`base-conflict` or `check-failed`: a fix worker as in 4, then finish again.

## 6. The PR gate's review

In the integration worktree, `codex-review-run --base main`. `gh pr create`
refuses a commit it has not covered, so nothing may be committed after it.
Findings to fix: a fix worker, then 5 and 6 again.

## 7. Push and open the PR

```bash
nix shell nixpkgs#nushell --command <skill-dir>/scripts/spec.nu push 412
```

Pushes `spec-412` and returns `closes` and each ticket's last commit message,
which carries its Decisions and Deferred. From the integration worktree, open
the PR in the repository's PR format with those decisions, ending with
`closes`. File the Deferred items as issues. Then `queue.nu add <pr>` and run
the queue; the tickets close when the PR lands.

## 8. CI fails on the spec's PR

The queue stops with `no-worker`: no worker holds the integration branch.
Find the ticket from the failing files:

```bash
git log --first-parent --merges --format='%h %s' spec-412
git diff --stat <merge>^1 <merge>^2 -- <failing path>
```

A flaky test goes per triage.md. Otherwise a fix worker as in 4, then 5, 6,
and `spec.nu push` again: the PR updates, and the queue picks it up when run
again.

## 9. After it lands

land.nu removes the integration worktree. Delete the ticket branches, which
`spec-412.json` in the state directory lists, then that file.
