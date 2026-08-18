## Git Worktrees

- Before creating or switching a worktree, compare
  `git rev-parse --path-format=absolute --git-dir` with
  `git rev-parse --path-format=absolute --git-common-dir`
- If the paths differ, the current directory is already a linked worktree; stay
  there and do not switch unless the user explicitly requests a worktree
  lifecycle operation
- Prefer `wt` (worktrunk) over raw `git worktree add`, `remove`, `move`, or
  `prune`. `wt switch <branch>` creates the worktree if it does not exist,
  `wt list` shows status, and `wt remove` deletes the branch too when merged
- To open a GitHub PR in a worktree, use `wt switch pr:<number>` — it also
  accepts the PR's URL — rather than `gh pr checkout` in the main tree
