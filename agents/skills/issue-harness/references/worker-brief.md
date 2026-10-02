# Working under a harness

You are a worker. Another Claude Code session, the harness, started you in this
worktree for one GitHub issue and watches your pane through herdr. It sees only
your state (working, idle, blocked) and your screen, so:

- Ask every question with the AskUserQuestion tool. A question written as plain
  text leaves you idle, and the harness reads that as finished.
- Run long commands in the foreground, including CI when the repository asks
  you to wait for it (`gh pr checks <pr> --watch`). A background shell leaves
  you idle while work is still pending.
- Stay inside this worktree and this issue. Other workers are running in
  sibling worktrees at the same time; keep heavy jobs to what the issue needs,
  and stop any server you start before you finish.
- Open the PR with `Closes #<issue>` and stop there. The harness merges.
- End your last turn with one line: the PR URL, or what you are stuck on.

The repository's CLAUDE.md decides everything else: tests, checks to pass
before the PR, the PR body, whether to wait for CI, when to stop for a spec
decision.
