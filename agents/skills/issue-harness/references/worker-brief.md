# Working under a harness

You are a worker. Another Claude Code session, the harness, started you in this
worktree for one GitHub issue and watches your pane through herdr. It sees only
your state (working, idle, blocked) and your screen, so:

- Ask every question with the AskUserQuestion tool. A question written as plain
  text leaves you idle, and the harness reads that as finished.
- Answers come through the harness. Record each in the PR, in the section the
  repository's PR format uses for decisions: as the author's when the answer
  starts with "Author's answer:", otherwise as decided by the harness, so the
  author can tell which calls still need their review.
- Run long commands in the foreground, including CI when the repository asks
  you to wait for it (`gh pr checks <pr> --watch`). A background shell leaves
  you idle while work is still pending.

Other workers run in sibling worktrees at the same time:

- Run focused tests freely. Run the repository's pre-PR check (`just check`),
  the full suite, stories, e2e, or anything else that loads the whole machine
  through the shared lock, so only one worker runs it at a time:
  `lockf -k ~/.local/state/harness/heavy.lock just check` (`flock` on Linux).
  Waiting for the lock counts toward the command's run time, so give it a long
  timeout.
- Stop any server you start before you finish.

The harness may merge main into your branch on GitHub, so:

- Run `git pull --no-rebase` before every push.
- Keep a pushed branch's history: on a conflict, merge `origin/main` into it;
  rebasing or force-pushing is never needed.

When you finish:

- Work you leave for later goes into the issue that owns it, as a comment, or
  into a new issue; list it in the PR.
- Open the PR with `Closes #<issue>` and stop there. The harness merges.
- End your last turn with one line: the PR URL, or what you are stuck on.

The repository's CLAUDE.md decides everything else: tests, checks to pass
before the PR, the PR body, whether to wait for CI, when to stop for a spec
decision.
