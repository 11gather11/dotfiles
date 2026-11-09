#!/usr/bin/env nu
# Has Codex review the current branch the way Matt Pocock's code-review does:
# against the repository's coding standards, and against the issues it
# implements, kept as two separate reports. The code is written by Claude
# workers; the review comes from the other vendor's model.
#
# This is not the PR gate. `codex-review-run` records the commit it covers and
# `gh pr create` checks for that record; run it after the fixes from this one.

use harness.nu [state-dir main-checkout]

# Matt's procedure, read by Codex from the installed plugin rather than
# copied here.
const procedure = "~/.config/claude/skills/mattpocock-skills/skills/engineering/code-review/SKILL.md"

# Review HEAD of the current worktree against `base`, with `issues` as the
# spec. Runs for minutes: start it in the background.
#
# Prints one JSON line last: `{result: reviewed, report, head, base}`, the
# report being a Markdown file with a Standards and a Spec section.
# Exit status: 0 reviewed; 1 error.
#
# @example
# review.nu 264                    # one issue, against the default branch
# review.nu --base main 412 415 416 # a spec and its tickets
def main [
    ...issues: int        # the issue, or the spec and its tickets; the Spec axis reads them
    --base: string        # the branch the work goes into; the default branch when omitted
] {
    let out = try { review $issues $base } catch {|e| {result: error, detail: $e.msg, next: "fix the cause, then run review.nu again"} }
    $out | to json --raw | print
    exit (if $out.result == "reviewed" { 0 } else { 1 })
}

def review [issues: list<int>, base]: nothing -> record {
    let dir = $env.PWD
    let repo = main-checkout
    let procedure_path = $procedure | path expand
    if not ($procedure_path | path exists) {
        error make {msg: $"($procedure_path) is missing: the mattpocock-skills plugin is not installed"}
    }
    let base = if $base != null { $base } else {
        ^gh repo view --json defaultBranchRef --jq .defaultBranchRef.name | str trim
    }
    ^git fetch --quiet origin $base | complete | ignore
    let fixed = $"origin/($base)"
    let head = ^git rev-parse HEAD | str trim
    if (^git diff --quiet $"($fixed)...HEAD" | complete).exit_code == 0 {
        error make {msg: $"nothing to review: HEAD has no changes against ($fixed)"}
    }

    let out_dir = state-dir $repo | path join reviews
    mkdir $out_dir
    let stem = $out_dir | path join ($head | str substring 0..<12)
    # The issues are fetched here, so Codex needs neither the tracker nor
    # network access for the Spec axis
    let spec_file = $"($stem)-issues.md"
    $issues | each {|n|
        let v = ^gh issue view $n --json number,title,body | complete
        if $v.exit_code != 0 { error make {msg: $"gh issue view ($n): ($v.stderr | str trim)"} }
        let i = $v.stdout | from json
        $"# #($i.number) ($i.title)\n\n($i.body)"
    } | str join "\n\n---\n\n" | save --force $spec_file

    let report = $"($stem)-review.md"
    let prompt = [
        $"Review the changes on this branch by following the procedure in ($procedure_path), with these differences:"
        $"- The fixed point is ($fixed): review `git diff ($fixed)...HEAD` and `git log ($fixed)..HEAD`."
        (if ($issues | is-empty) {
            "- There is no spec: skip the Spec axis and say so."
        } else {
            $"- The spec is in ($spec_file): the issues this branch implements. Do not look for it in the issue tracker."
        })
        "- Run the Standards and Spec axes separately, with a sub-agent each if you can start them."
        "- Change no file and run nothing that writes. This is a review only."
        "- Your final message is the report: `## Standards`, then `## Spec`, then the one-line summary."
    ] | str join "\n"
    let r = $prompt | ^codex exec --sandbox read-only -C $dir -o $report - | complete
    if $r.exit_code != 0 or not ($report | path exists) {
        error make {msg: $"codex exec failed \(exit ($r.exit_code)\): ($r.stderr | lines | last 5 | str join ' ')"}
    }
    {
        result: reviewed
        report: $report
        head: $head
        base: $fixed
        next: "read the report; fix what is this branch's to fix, then run codex-review-run for the PR gate"
    }
}
