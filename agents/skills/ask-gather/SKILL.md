---
name: ask-gather
description: Ask which skill or flow fits your situation on this machine. Matt Pocock's map (ask-matt), with harness workers, wt worktrees, Codex reviews and one CI run per spec.
disable-model-invocation: true
---

# Ask gather

Matt Pocock's skills are the map here. Read
`~/.config/claude/skills/mattpocock-skills/skills/engineering/ask-matt/SKILL.md`
first, and the SKILL.md of any skill before saying what it does. This page holds
only where this machine's flow differs; where it says nothing, ask-matt holds.

Matt's skills are namespaced: `/mattpocock-skills:<name>`.

## Where the flow differs

- **Implementers are workers, not subagents.** Each is a full Claude Code
  session in its own terminal (a herdr pane, or a herdr-app tab) and wt
  worktree: the user can open it and talk to it, and it runs with the user's
  hooks. `/issue-harness` starts and supervises them.
- **A spec goes through `/issue-harness`, not `/implement-spec`.** After
  `/to-tickets`, give `/issue-harness` the spec's issue number. Its tickets
  merge into one local integration branch after a local check, and the spec
  reaches main as one PR, so CI runs once per spec.
- **A single issue goes through `/issue-harness` too**, one worker and one PR,
  pushed once when it is done. Something small enough to do in this session
  needs no harness: `tdd`, or `/mattpocock-skills:diagnosing-bugs` for a bug.
- **A prototype gates what it can change.** While a prototype issue is open,
  every ticket whose shape its answer could change is blocked by it; tickets
  that run beside it touch only what no answer can move. When tickets add
  instances of one mechanism (styles, providers, plugins), one ticket first
  gives the mechanism every hook the prototype's instances need, and the
  instance tickets are blocked by it. Otherwise each instance invents or
  defers the missing hook, and the fix lands later as rework.
- **TDD is the local `tdd`**, not `/mattpocock-skills:tdd`: Matt's stops to
  agree each seam with the user, which a worker under a harness cannot.
- **Codex reviews; Claude writes.** In place of `/code-review`, the harness and
  its workers run issue-harness's `review.nu` (Matt's Standards and Spec axes,
  by Codex), then `codex-review-run`. A hook refuses `gh pr create` from a
  commit no Codex review covered.
- **Worktrees are wt**: `wt switch`, `wt remove`, `wt switch pr:<n>`.
- **Commits and PRs** go through the `commit` and `create-pr` skills.
- **Retros sort their findings.** `/mattpocock-skills:retro` as usual; what
  slowed down `/issue-harness` itself goes in
  `~/.local/state/harness/<repo>/retro.md`, which the next revision of that
  skill reads.

## A new repository

Once, before the first issue:

1. Create it with squash merges allowed. Make the CI's final job required on
   main in a ruleset, with no approvals required: one account opens and merges
   every PR. If merges need a person, the harness runs with `no-land`.
2. Ask the user whether agents may sign commits here; if so, they add it to
   `~/.gitconfig.ai-signing`.
3. `/mattpocock-skills:setup-matt-pocock-skills`, then the repository's own
   CLAUDE.md: the checks before a PR, lint and type check commands, PR format.
4. Write `~/.local/state/harness/<repo>/check`: the command a ticket must pass
   before it joins a spec's integration branch.
5. `/issue-harness` runs its `setup.nu` at the start of every batch; it reports
   what is still missing.

## Answering

Place the user on ask-matt's map, apply the differences above, and name the
next skill to run and why. When the next step is a build, say whether it is a
spec (to `/issue-harness` with the spec number) or a single issue.
