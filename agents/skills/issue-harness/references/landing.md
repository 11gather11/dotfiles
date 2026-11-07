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
