# Working under a harness

You are a worker. Another Claude Code session, the harness, started you in this
worktree for one GitHub issue and watches your pane through herdr. It sees only
your state (working, idle, blocked) and your screen, so:

- Ask the harness in plain text, not with the AskUserQuestion tool, and end
  your turn there. The harness reads the turn of every worker that stops;
  a dialog can only be answered with keystrokes, one option at a time.
- Answers come through the harness. Record each in the PR, in the section the
  repository's PR format uses for decisions: as the author's when the answer
  starts with "Author's answer:", otherwise as decided by the harness, so the
  author can tell which calls still need their review.
- Run long commands in the foreground with the Bash tool's `timeout: 600000`.

Other workers run in sibling worktrees at the same time:

- Run focused tests freely. Run the repository's pre-PR check (`just check`),
  the full suite, stories, e2e, or anything else that loads the whole machine
  through the shared lock, so only one worker runs it at a time:
  `lockf -k -t 300 ~/.local/state/harness/heavy.lock just check` (on Linux,
  `flock -w 300`). The lock wait counts toward the Bash tool's 10-minute limit,
  so it is capped at 5 minutes; exit status 75 means the wait ran out, not that
  the check failed. Run the same command again.
- Stop any server you start before you finish.

The harness may merge main into your branch on GitHub, so:

- Run `git pull --no-rebase` before every push.
- Keep a pushed branch's history: on a conflict, merge `origin/main` into it;
  rebasing or force-pushing is never needed.

When you finish:

- List work you leave for later in a "Deferred" section of the PR body, one
  item each, naming the issue that owns it if one does. It is for work outside
  this issue: whatever this PR needs to be right, such as pulling in files CI
  generated for it, is yours to finish. You cannot write issues or issue
  comments; the harness files them before it lands the PR.
- Open the PR with `Closes #<issue>` and stop there, without waiting for CI,
  even where the repository's CLAUDE.md asks you to: the harness waits on CI,
  sends you any failure, and merges. A worker waiting on CI holds a slot that
  another worker could use.
- End your last turn with one line: the PR URL, or what you are stuck on.

The repository's CLAUDE.md decides everything else: tests, checks to pass
before the PR, the PR body, when to stop for a spec decision.
