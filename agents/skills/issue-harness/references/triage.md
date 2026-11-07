# Triage

## Questions and permission prompts

Workers ask in plain text and stop; answer with a prompt.

Answer a question yourself only when something already decides it: the issue,
its parent spec, the ADRs, GLOSSARY.md, or a rule in the repository's CLAUDE.md
for settling open questions (such as following a reference product). Otherwise
bring it to the user, with the options and your recommendation.

Answer a permission prompt only within what the user's settings already allow.

A permission prompt, or a dialog a worker opened anyway, is answered on its screen:

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

The queue sends each failure to its worker first, and reruns the failed jobs
once when the worker answers that the failure is not the PR's. You decide when
the worker stops without either (`no-progress`), when the queue reports
`flaky`, or when you land by hand. Decide whose failure it is from the failed
log:

- **Caused by the PR**: send the worker the failing job name and the lines that
  matter.
- **Load, not code**: a timeout on a busy runner (`Test timed out`, `Could not
capture a stable screenshot`) that names no line of the PR. A real
  difference fails the same way each run, such as the same number of pixels
  off in a screenshot; a load failure moves between tests and runs.
- **Unrelated and intermittent** (code the PR does not touch, passed before),
  including load:
  `gh run rerun <run> --failed`, once (the queue has done so on `flaky`).
  A flake gets an issue rather than another rerun, which would only hide it.
  If no issue covers it yet
  (`gh issue list --search "<test name>"`), file one with the repository's
  triage label. Leave it for the user to schedule rather than starting a worker
  for it in this batch, unless the user has left you to run the batch through
  unattended: then start a `diagnosing-bugs` worker for it, so the flake does
  not keep stalling the issues behind it.
- **Fails again after the rerun**: look at main's latest run. Failing the same
  way there means main is broken: stop landing and bring it to the user.
  Otherwise it is a flake as above, and the PR waits for its fix.

## Checks the base does not require

`optional-failed` means every required check passed and only others failed.
Read the failed job. If it never ran (hosted-runner minutes used up, no
runner online) or fails the same way on main, it says nothing about the PR:
let it land (`queue.nu allow-optional <pr>`, or `land.nu --allow-optional`
by hand) and file the job's breakage as an issue if none
covers it. If the PR caused it, send it back as for any failure.

## After the base was merged in

A PR whose base was merged in on GitHub (`updated`) can conflict in meaning
where no line conflicts: a key added twice, a reference to something the base
renamed. Only its next CI run catches that, so wait for it before landing.
