#!/usr/bin/env nu
# Lands one worker's PR: reads its state and checks, brings a stale base up to
# date, merges, pulls and removes the worker's worktree. Stops with a classified
# result wherever the harness has to decide. Prints one JSON record.

const gh_tries = 3
const gh_delay = 5sec
const poll_tries = 6
const poll_delay = 10sec
const pr_fields = "number,state,isDraft,mergeable,headRefOid,headRefName,baseRefName,url"
const check_fields = "name,state,bucket,workflow,link,completedAt"

# Error code that marks "GitHub or the remote could not be read", as opposed to
# a bug or a bad argument
const unknown_code = "land::unknown"

# Land a worker's PR, or say what the harness has to do first.
# Prints one JSON line with `result`, `pr`, `sha`, `detail` and `next`.
# Exit status: 0 landed, merged or would-*; 2 the harness has to act; 1 error.
def main [
    pr?: string     # PR number or URL
    --agent: string # herdr agent of the worker, to find its worktree
    --dry-run       # classify and report what would happen; change nothing
] {
    let r = try {
        if $pr == null { error make {msg: "usage: land.nu <pr> [--agent <name>] [--dry-run]"} }
        land $pr $agent $dry_run
    } catch {|e|
        if $e.details.code? == $unknown_code {
            (report
                unknown
                $pr
                null
                $e.msg
                "run land.nu again; act on nothing until the PR reads"
            )
        } else {
            (report
                error
                $pr
                null
                $e.msg
                "fix the invocation, or bring the error to the user"
            )
        }
    }
    # A single line survives callers that keep only the tail of the output
    $r | to json --raw | print
    exit (exit-code $r.result)
}

# Maps a result to the exit status the harness branches on.
def exit-code [result: string]: nothing -> int {
    match $result {
        "landed" | "merged" | "would-merge" | "would-update" => 0
        error => 1
        _ => 2
    }
}

# Builds the one record every outcome prints.
def report [
    result: string
    pr: any        # the PR number once read, else the argument as given
    sha: any       # head commit the result is about, or null
    detail: string
    next: string   # what the harness should run or do next
]: nothing -> record {
    {
        result: $result
        pr: $pr
        sha: $sha
        detail: $detail
        next: $next
    }
}

# Runs gh until `parse` turns its `complete` record into a value.
# A failed call says nothing about the PR, so after the last try this raises
# the unknown error instead of letting a caller read the failure as "open" or
# "not merged".
def gh-read [
    what: string
    args: list<string>
    parse: closure
    --tries: int = 3
]: nothing -> any {
    let r = ^gh ...$args | complete
    let v = try { do $parse $r } catch { null }
    if $v != null { return $v }
    if $tries <= 1 {
        error make {
            msg: $"gh could not ($what): ($r.stderr | str trim)"
            code: $unknown_code
        }
    }
    sleep $gh_delay
    gh-read $what $args $parse --tries ($tries - 1)
}

# Parses a successful gh call's JSON stdout; null for a failed one.
def gh-ok-json [r: record]: nothing -> any {
    if $r.exit_code == 0 {
        $r.stdout | from json
    }
}

# Reads the PR, polling while GitHub is still computing `mergeable`.
# A merged or closed PR keeps `UNKNOWN` forever, and a draft is reported before
# mergeability, so neither waits.
def read-pr [pr: string, --tries: int = 6]: nothing -> record {
    let v = (gh-read
        "read the PR"
        [pr view $pr --json $pr_fields]
        {|r| gh-ok-json $r }
    )
    if $v.state != "OPEN" or $v.isDraft or $v.mergeable != "UNKNOWN" or $tries <= 1 {
        return $v
    }
    sleep $poll_delay
    read-pr $pr --tries ($tries - 1)
}

# Reads the checks on the PR's current head.
# `gh pr checks` exits non-zero for failing or pending checks and still prints
# the JSON, so the exit status is no guide; an empty stdout with "no checks
# reported" is the one non-JSON answer that is not a failure.
def read-checks [pr: string]: nothing -> table {
    gh-read "read the checks" [pr checks $pr --json $check_fields] {|r|
        let out = $r.stdout | str trim
        match $out {
            $o if ($o | str starts-with "[") => ($o | from json)
            "" if ($r.stderr =~ "no checks reported") => []
            _ => null
        }
    }
}

# Drops the cancelled runs that a finished or running sibling replaces.
# One commit can get two runs of the same job, one of them cancelled by the
# concurrency group; the other one is the verdict. A cancelled check with no
# sibling never ran at all, so it stays and counts as a failure.
def effective-checks [checks: table]: nothing -> table {
    if ($checks | is-empty) { return [] }
    $checks
    | group-by --to-table workflow name
    | each {|g|
        let ran = $g.items | where bucket != "cancel"
        if ($ran | is-empty) { $g.items } else { $ran }
    }
    | flatten
}

# Sums up a head's checks: `none`, `pending`, `failed` or `passed`, with the
# failed checks and the run each belongs to.
# Skipped is a pass: a docs-only PR skips the heavy jobs on purpose.
def classify-checks [checks: table]: nothing -> record {
    let eff = effective-checks $checks
    let failed = $eff
    | where bucket not-in ["pass" "skipping" "pending"]
    | each {|c|
        {
            name: $c.name
            workflow: $c.workflow
            link: $c.link
            run: ($c.link | parse --regex 'actions/runs/(?<run>\d+)' | get -o 0.run)
        }
    }
    let status = if ($eff | is-empty) {
        "none"
    } else if ($eff | any {|c| $c.bucket == "pending" }) {
        "pending"
    } else if ($failed | is-not-empty) {
        "failed"
    } else {
        "passed"
    }
    {status: $status, failed: $failed}
}

# Runs git and returns its trimmed stdout, raising on failure.
def git-out [repo: string, args: list<string>]: nothing -> string {
    let r = ^git -C $repo ...$args | complete
    if $r.exit_code != 0 {
        error make {msg: $"git ($args | str join ' ') failed: ($r.stderr | str trim)"}
    }
    $r.stdout | str trim
}

# Compares the base as the PR's CI saw it with the base now. Returns whether
# the base moved and which files both sides changed since the merge base.
# The PR's side is diffed at `sha`, the commit whose checks were evaluated.
def base-drift [repo: string, pr: record]: nothing -> record {
    let base = $pr.baseRefName
    let remote_base = $"refs/remotes/origin/($base)"
    # The pull ref also reaches a head pushed from a fork
    let fetch = ^git -C $repo fetch --quiet origin $"+refs/heads/($base):($remote_base)" $"refs/pull/($pr.number)/head" | complete
    if $fetch.exit_code != 0 {
        error make {
            msg: $"git fetch failed: ($fetch.stderr | str trim)"
            code: $unknown_code
        }
    }
    let mb = git-out $repo [merge-base $remote_base $pr.headRefOid]
    let tip = git-out $repo [rev-parse $remote_base]
    if $mb == $tip {
        return {
            moved: false
            overlap: []
        }
    }
    let base_files = git-out $repo [diff --name-only $mb $tip] | lines
    let overlap = git-out $repo [diff --name-only $mb $pr.headRefOid]
    | lines
    | where $it in $base_files
    {moved: true, overlap: $overlap}
}

# Finds the worker's worktree: the herdr agent's directory when one is named,
# else the worktree checked out on the PR's branch. Errors when neither is a
# linked worktree of this repository, so the main checkout is never removed.
def find-worktree [repo: string, branch: string, agent]: nothing -> string {
    let from_agent = if $agent != null {
        let r = ^herdr agent get $agent | complete
        if $r.exit_code == 0 {
            let cwd = $r.stdout | from json | get -o result.agent.cwd
            if $cwd != null {
                ^git -C $cwd rev-parse --show-toplevel
                | complete
                | if $in.exit_code == 0 { $in.stdout | str trim }
            }
        }
    }
    let path = if $from_agent != null {
        $from_agent
    } else {
        ^wt -C $repo list --format=json
        | from json
        | get items
        | where branch == $branch
        | get -o 0.worktree.path
    }
    if $path == null {
        error make {msg: $"no worktree found for branch ($branch)"}
    }
    let common = git-out $path [rev-parse --path-format=absolute --git-common-dir] | path dirname
    if $common != $repo {
        error make {msg: $"($path) is not a worktree of ($repo)"}
    }
    if $path == $repo {
        error make {msg: "refusing to remove the main checkout"}
    }
    $path
}

# Pulls the merge into the main checkout and removes the worker's worktree.
# Returns the fields to merge into the `landed` record; a failure here is a
# `cleanup_error`, since the merge itself has already happened.
def clean-up [repo: string, branch: string, agent]: nothing -> record {
    let pull = ^git -C $repo pull --quiet --ff-only | complete
    let pull_error = if $pull.exit_code != 0 { $"git pull --ff-only: ($pull.stderr | str trim)" }
    let removed = try {
        let path = find-worktree $repo $branch $agent
        # wt's remove hook also closes the worker's herdr workspace
        let r = ^wt -C $repo remove --format=json $path | complete
        if $r.exit_code != 0 {
            {
                worktree: $path
                error: $"wt remove: ($r.stderr | str trim)"
            }
        } else {
            let out = try {
                $r.stdout | from json
            } catch { {} }
            {
                worktree: $path
                branch_outcome: ($out.branch_outcome? | default null)
                error: null
            }
        }
    } catch {|e| {worktree: null, error: $e.msg} }
    let errors = [$pull_error $removed.error] | compact
    $removed
    | reject error
    | merge (
        if ($errors | is-empty) { {} } else { {
            cleanup_error: ($errors | str join "; ")
        } }
    )
}

# Walks the PR through every check in precedence order and acts on the first
# that applies.
def land [pr_arg: string, agent, dry_run: bool]: nothing -> record {
    # The main checkout, even when called from a linked worktree
    let repo = git rev-parse --path-format=absolute --git-common-dir | path dirname
    cd $repo

    let pr = read-pr $pr_arg
    let n = $pr.number
    # Everything below is judged against this one commit, and the merge is
    # pinned to it: if the worker pushes after this read, GitHub refuses the
    # merge instead of landing checks that were never run on the new head
    let sha = $pr.headRefOid
    let base = $pr.baseRefName
    let say = {|result: string, detail: string, next: string| report $result $n $sha $detail $next }

    if $pr.state == "MERGED" {
        return (
            (do
                $say
                merged
                $"($pr.url) is already merged"
                $"nothing to land; `wt remove ($pr.headRefName)` if its worktree remains"
            )
        )
    }
    if $pr.state != "OPEN" {
        return (
            (do
                $say
                closed
                $"($pr.url) is ($pr.state | str lowercase) without a merge"
                "bring it to the user"
            )
        )
    }
    if $pr.isDraft {
        return (
            (do
                $say
                draft
                $"($pr.url) is a draft"
                "wait for the worker to mark it ready, then land.nu again"
            )
        )
    }
    match $pr.mergeable {
        "UNKNOWN" => {
            return (
                (do
                    $say
                    unknown-mergeable
                    $"GitHub has not computed mergeability after ($poll_tries) reads ($poll_delay) apart"
                    "run land.nu again in a minute"
                )
            )
        }
        "CONFLICTING" => {
            return (
                (do
                    $say
                    conflict
                    $"($pr.headRefName) conflicts with ($base)"
                    $"ask the worker to merge origin/($base) into its branch and push \(no rebase, no force push\), then land.nu again"
                )
            )
        }
    }

    let checks = classify-checks (read-checks $pr_arg)
    match $checks.status {
        "none" => {
            return (
                (do
                    $say
                    no-checks
                    "no checks are registered on the head yet"
                    $"wait ~30 s and run land.nu again, or `gh pr checks ($n) --watch --fail-fast`"
                )
            )
        }
        "pending" => {
            return (
                (do
                    $say
                    pending
                    "checks are still running"
                    $"`gh pr checks ($n) --watch --fail-fast` in the background, then land.nu again"
                )
            )
        }
        "failed" => {
            let names = $checks.failed | get name | str join ", "
            return (
                do $say ci-failed $"failed: ($names)" "read `gh run view <run> --log-failed`; send it back if the PR caused it, else `gh run rerun <run> --failed`"
                | insert failed $checks.failed
            )
        }
    }

    let drift = base-drift $repo $pr
    if $drift.moved and ($drift.overlap | is-not-empty) {
        let files = $drift.overlap | str join ", "
        if $dry_run {
            return (
                do $say would-update $"($base) moved and changed files this PR touches: ($files)" $"run land.nu without --dry-run to `gh pr update-branch ($n)`"
                | insert overlap $drift.overlap
            )
        }
        # A merge of the base on GitHub, not a rebase: nobody force-pushes, and
        # the worker's next pull is a fast-forward
        let u = ^gh pr update-branch $pr_arg | complete
        if $u.exit_code != 0 {
            return (
                (do
                    $say
                    update-failed
                    $"gh pr update-branch: ($u.stderr | str trim)"
                    $"on a conflict, ask the worker to merge origin/($base) and push; otherwise land.nu again"
                )
            )
        }
        return (
            do $say updated $"merged ($base) into the PR because it changed files the PR touches: ($files)" $"wait for the new CI with `gh pr checks ($n) --watch --fail-fast`, then land.nu again"
            | insert overlap $drift.overlap
        )
    }

    if $dry_run {
        return (
            (do
                $say
                would-merge
                "mergeable, checks pass, and the base does not overlap"
                $"run land.nu without --dry-run to squash-merge at ($sha)"
            )
        )
    }

    let m = ^gh pr merge $pr_arg --squash --match-head-commit $sha | complete
    if $m.exit_code != 0 {
        # Read again rather than parse gh's message: a moved head and a merge
        # that happened despite the error both show in the PR itself
        let now = (gh-read
            "read the PR after a refused merge"
            [pr view $pr_arg --json "state,headRefOid"]
            {|r| gh-ok-json $r }
        )
        if $now.state != "MERGED" {
            if $now.headRefOid != $sha {
                return (
                    (do
                        $say
                        head-moved
                        $"the head moved to ($now.headRefOid) after the checks were read"
                        "land.nu again"
                    )
                )
            }
            return (
                (do
                    $say
                    merge-refused
                    $"gh pr merge: ($m.stderr | str trim)"
                    "read the detail; branch protection or a review may be blocking it"
                )
            )
        }
    }

    (do
        $say
        landed
        $"squash-merged ($pr.url) at ($sha)"
        "nothing; note the merge for the batch summary"
    )
    | merge (clean-up $repo $pr.headRefName $agent)
}
