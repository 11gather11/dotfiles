## You are Codex

The brief above was written for a Claude Code worker. You are Codex, and this
overrides it where the two differ:

- Where it names a Claude Code tool (AskUserQuestion, the Bash tool's
  timeout), do the same with your own: ask in plain text and end your turn;
  run long commands to the end in the foreground.
- Your code is reviewed by Claude, the other vendor's model, not by Codex.
  Before you open the PR, run
  `nix shell nixpkgs#nushell --command <skill-dir>/scripts/review.nu --by claude <issue>`
  (it takes minutes) and fix what is this PR's to fix. Then run
  `claude-review-run --base <base branch>` last, after your final commit:
  `gh pr create` refuses a commit Claude has not reviewed, and a Codex review
  does not count for code you wrote.
- Do not start a review with your own subagents in place of these: a review
  by Codex of Codex's work is what the gate does not accept.
