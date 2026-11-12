# Migrations

Each section is a change to this skill that a repository already run with it
has to catch up on. `setup.nu` lists the ones a repository has not done yet;
the harness carries them out, then records each with
`setup.nu migrated <id>`. A repository the harness has never run in starts
with all of them recorded.

Add a section when a change leaves something behind in a repository or its
state directory: a setting, a workflow, open PRs. Write steps that can be done
again harmlessly. Delete a section once every repository has done it.

## 2026-11-09-drop-draft-prs Workers no longer open drafts

The `draft-prs` setting is gone: workers push once, when the PR is ready to
open, so drafts no longer save CI.

- Mark any draft PR a worker opened ready (`gh pr list --draft`, then
  `gh pr ready <n>`) before it goes in the queue; queue.nu skips drafts.
- Tell each running worker that has not opened its PR yet to open a regular
  one, not a draft.
- If the repository's CI was changed for drafts (jobs skipped on drafts,
  `ready_for_review` among the triggers), have a worker revert it: a required
  check skipped on a draft reads as passed once the PR is readied.
- `rm ~/.local/state/harness/<repo>/draft-prs`

## 2026-11-13-queue-run Running the queue takes `queue.nu run`

A bare `queue.nu` now only lists the queue, and one runner holds a
repository's queue at a time. PR bodies mark what the author has to verify
with `<!-- needs-author -->`, which `queue.nu add` refuses without
`--verified`.

- If a queue runner from before this change is still running in the
  background, stop it and start `queue.nu run` instead.
- Read the PRs already queued (`queue.nu list`) and every open worker PR: one
  that asks the author to verify something but has no `<!-- needs-author -->`
  is taken off the queue (`queue.nu remove <n>`) until the author has.
- Tell each running worker that has not opened its PR yet about the marker
  (the brief they started with does not have it).
