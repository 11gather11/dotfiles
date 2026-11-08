#!/usr/bin/env nu
# Checks what the harness takes for granted in a repository before its first
# batch, and which settings fit it. Changes nothing: the settings are markers
# the user places, and the repository's rules are theirs.

use harness.nu [state-dir setting-on main-checkout required-checks]

# Check the repository of the current directory.
#
# Prints one JSON line last: `{result, repo, checks, settings}`. `result` is
# `ok` or `needs-attention`; each check is `{name, ok, detail}`, or
# `{name, ok, next}` when it fails, and
# `settings` lists the markers in `~/.local/state/harness/<repo>/` that fit.
# Exit status: 0 ok; 2 something needs attention; 1 error.
#
# @example
# setup.nu
def main [] {
    let out = try { check-all } catch {|e| {result: error, detail: $e.msg, next: "fix the cause, then run setup.nu again"} }
    $out | to json --raw | print
    exit (match $out.result {
        ok => 0
        error => 1
        _ => 2
    })
}

def check-all []: nothing -> record {
    let repo = main-checkout
    cd $repo
    let gh = ^gh repo view --json nameWithOwner,defaultBranchRef,squashMergeAllowed | complete
    if $gh.exit_code != 0 {
        error make {msg: $"gh repo view: ($gh.stderr | str trim); log in with `gh auth login` and run it from a GitHub checkout"}
    }
    let info = $gh.stdout | from json
    let base = $info.defaultBranchRef.name
    let approvals = required-approvals $base
    let draft_trigger = workflows-run-on-ready $repo
    let no_land = setting-on $repo no-land
    let draft_prs = setting-on $repo draft-prs

    let checks = [
        (
            (check
                "herdr"
                ($env.HERDR_ENV? == "1")
                "this session runs inside herdr"
                "start the harness from a herdr pane; workers are started and read through it"
            )
        )
        (
            check "required checks" (required-checks $base | is-not-empty)
            $"($base) requires: (required-checks $base | str join ', ')"
            $"require the CI's final job on ($base) in a ruleset: without one, land.nu reads a head whose checks are still being created as passed"
        )
        (
            check "squash merge" $info.squashMergeAllowed
            "squash merges are allowed"
            "allow squash merging in the repository settings; land.nu lands with `gh pr merge --squash`"
        )
        (
            check "approvals" ($approvals == 0 or $no_land)
            (if $approvals == 0 { "no approval is required to merge" } else { $"($approvals) approval\(s\) required, and no-land is set" })
            $"($base) requires ($approvals) approval\(s\), which nobody gives when one account opens and merges: set no-land, or require none"
        )
        (
            check "signing" (signs-for-agents $repo)
            "commits here sign with the key that needs no approval"
            $"ask the user whether agents may sign for this repository; if so, add an includeIf for ($repo)/ to ~/.gitconfig.ai-signing"
        )
        (
            check "CLAUDE.md" ([CLAUDE.md AGENTS.md] | any {|f| $repo | path join $f | path exists })
            "the repository has its own instructions"
            "write the repository's CLAUDE.md: the checks to pass before a PR and the PR format; the worker brief defers to it"
        )
        (
            check "draft-prs trigger" (not $draft_prs or $draft_trigger)
            (if $draft_prs { "draft-prs is set and a workflow runs on ready_for_review" } else { "draft-prs is not set" })
            "draft-prs is set but no workflow runs on `ready_for_review`: a readied PR gets no full CI and the queue waits forever. Add the trigger, or remove the marker"
        )
    ]

    let state = state-dir $repo
    let settings = [
        (if $approvals > 0 and not $no_land {
            {marker: no-land, why: "merging needs an approval the harness cannot give", place: $"touch ($state)/no-land"}
        })
        (if $draft_trigger and not $draft_prs {
            {marker: draft-prs, why: "a workflow runs on ready_for_review; if drafts run light jobs only, workers can open drafts", place: $"touch ($state)/draft-prs"}
        })
    ] | compact

    let failing = $checks | where not ok
    {
        result: (if ($failing | is-empty) { "ok" } else { "needs-attention" })
        repo: $info.nameWithOwner
        checks: $checks
        settings: $settings
        next: (
            if ($failing | is-empty) { "start workers with spawn.nu" } else { "settle each check that is not ok, then run setup.nu again" }
        )
    }
}

def check [
    name: string
    ok: bool
    detail: string
    next: string
]: nothing -> record {
    if $ok { {name: $name, ok: true, detail: $detail} } else { {name: $name, ok: false, next: $next} }
}

# Approvals the base requires from its rulesets or its classic protection.
def required-approvals [base: string]: nothing -> int {
    let rules = ^gh api $"repos/{owner}/{repo}/rules/branches/($base)" | complete
    let from_rules = if $rules.exit_code == 0 {
        $rules.stdout | from json | where type == "pull_request" | get -o parameters.required_approving_review_count | default []
    } else { [] }
    let classic = ^gh api $"repos/{owner}/{repo}/branches/($base)/protection/required_pull_request_reviews" | complete
    let from_classic = if $classic.exit_code == 0 {
        [
            (
                $classic.stdout
                | from json
                | get -o required_approving_review_count
                | default 0
            )
        ]
    } else { [] }
    $from_rules | append $from_classic | append 0 | math max
}

# Whether any workflow lists `ready_for_review` among its triggers.
def workflows-run-on-ready [repo: string]: nothing -> bool {
    let dir = $repo | path join .github workflows
    if not ($dir | path exists) { return false }
    glob $"($dir)/*.{yml,yaml}" | any {|f| open --raw $f | str contains "ready_for_review" }
}

# Whether commits in `repo` pick the agent signing key, which needs no Touch ID.
def signs-for-agents [repo: string]: nothing -> bool {
    let r = ^git -C $repo config --show-origin user.signingkey | complete
    $r.exit_code == 0 and ($r.stdout | str contains "ai-signing")
}
