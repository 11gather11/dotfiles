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
