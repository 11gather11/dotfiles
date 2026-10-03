# Triage

## Questions and permission prompts

Answer a question yourself only when something already decides it: the issue,
its parent spec, the ADRs, CONTEXT.md, or a rule in the repository's CLAUDE.md
for settling open questions (such as following a reference product). Otherwise
bring it to the user, with the options and your recommendation.

Answer a permission prompt only within what the user's settings already allow.

On the worker's screen:

- Pick an option with `herdr agent send-keys <name> <number>`, then read the
  screen again before the next key.
- With two or more questions a "Review your answers" screen follows. Send `1`
  (Submit) there, or nothing is answered.
- To give an answer that is not one of the options, including the user's own
  answer, close the dialog with `herdr agent send-keys <name> esc` and send the
  answer as a prompt. Start it with "Author's answer:" when it is the user's, so
  the worker records it as theirs rather than yours.

## Prompts

`herdr agent prompt --wait` on its own waits for the whole turn to end, which
blocks you for as long as the worker works; `--until working --until blocked`
waits only for receipt. Without `--wait` a dropped prompt goes unnoticed, and the next
`agent wait` returns at once on the old `idle`. `agent_prompt_stalled` or
`timeout` does not prove the prompt was lost: check `herdr agent get` and
`herdr agent read` before sending it again.

## CI failures

Decide whose failure it is from the failed log:

- **Caused by the PR**: send the worker the failing job name and the lines that
  matter.
- **Unrelated and intermittent** (code the PR does not touch, passed before):
  `gh run rerun <run> --failed`, once. If no issue covers it yet
  (`gh issue list --search "<test name>"`), file one with the repository's
  triage label. Leave it for the user to schedule rather than starting a worker
  for it in this batch.
- **Fails again, or fails the same way on main**: main is broken. Stop landing
  and bring it to the user.
