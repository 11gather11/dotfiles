## Git Worktrees

- Use the `git-wt` skill for all worktree lifecycle operations
- Prefer `git wt` over raw `git worktree add`, `remove`, `move`, or `prune`
- To open a GitHub PR in a worktree, use `git wtpr <number|url>` (see the
  `git-wtpr` skill) rather than `gh pr checkout` in the main tree
