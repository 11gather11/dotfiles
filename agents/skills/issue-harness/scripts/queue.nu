#!/usr/bin/env nu
# The landing queue. The harness adds PRs it has read and approved; this
# lands them one after another, asks their workers to merge the base or fix CI,
# and returns only when the harness is needed. The decisions are in
# queue-rules.nu; this file reads GitHub and herdr and carries them out.

use harness.nu [state-dir setting-on main-checkout worker-of worker-state]
use queue-rules.nu [decide]

const land_script = path self land.nu
# A land.nu verdict is reused while the PR, its checks and the base look the
# same, so a quiet pass costs one `gh pr list`; this bounds how stale it gets.
const verdict_ttl = 10min
const prompt_timeout_ms = "30000"
# What a worker writes, at the start of a line, when it judges a CI failure
# not its PR's. The queue reads it rather than guessing from free text.
const not_this_pr_mark = "NOT-THIS-PR:"

# Run the queue until every PR has landed or the harness is needed.
#
# Prints one JSON line last: `{result, pr, agent, sha, detail, next, landed}`,
# `landed` being the PR numbers this run landed (queue-state.json keeps the
# rest). `result` is `done` when the queue is empty, otherwise what stopped it
# (`blocked`, `no-progress`, `flaky`, `ci-failed` …, or `timeout`).
# Exit status: 0 done; 2 the harness has to act; 1 error.
#
# @example
# queue.nu add 1189 1190
# queue.nu                # in the background; wakes the harness when needed
# queue.nu --dry-run      # one pass: what each PR would get, changing nothing
def main [
    --dry-run                     # one pass that reports and changes nothing
    --interval: duration = 90sec  # pause between passes
    --timeout: duration = 3hr     # return `timeout` after this, to be run again
] {
    let repo = main-checkout
    cd $repo
    let out = try {
        if $dry_run { dry-run $repo } else { run-queue $repo $interval $timeout }
    } catch {|e| {result: error, detail: $e.msg, next: "fix the cause, then run queue.nu again"} }
    $out | to json --raw | print
    exit (match $out.result {
        done | dry-run => 0
        error => 1
        _ => 2
    })
}

# Queue PRs after the harness has read them: no spec decision left open, and
# deferred work filed as issues.
def "main add" [...prs: int] {
    let repo = main-checkout
    let st = load-state $repo
    let q = load-queue $repo
    save-queue $repo ($q | update prs { append $prs | uniq | where $it not-in $st.dropped })
    main list
}

# Take PRs off the queue.
def "main remove" [...prs: int] {
    let repo = main-checkout
    let q = load-queue $repo
    save-queue $repo ($q | update prs { where $it not-in $prs })
    main list
}

# Let a PR land although checks the base does not require failed, for its
# current head only: the harness read the failure and found it not the PR's.
def "main allow-optional" [pr: int] {
    let repo = main-checkout
    let sha = ^gh pr view $pr --json headRefOid --jq .headRefOid | str trim
    let q = load-queue $repo
    save-queue $repo ($q | update allow_optional { upsert ($pr | into string) $sha })
    main list
}

# Show the queue, the asks made so far and what has landed.
def "main list" [] {
    let repo = main-checkout
    let st = load-state $repo
    let q = load-queue $repo
    {
        queue: ($q.prs | where $it not-in $st.dropped)
        allow_optional: $q.allow_optional
        asks: $st.asks
        landed: $st.landed
    } | to json --raw | print
}

# ── state ──
# The queue file is written only by add, remove and allow-optional, and the
# run's state only by the run, so the harness can change the queue while it
# runs. Both carry the checkout's path: the state directory is named after the
# checkout's directory, which two repositories can share.

def queue-file [repo: string]: nothing -> string {
    state-dir $repo | path join queue.json
}
def state-file [repo: string]: nothing -> string {
    state-dir $repo | path join queue-state.json
}

# Opens a state file written for `repo`, refusing one written for another
# checkout of the same name.
def open-for [repo: string, f: string, empty: record]: nothing -> record {
    if not ($f | path exists) { return ($empty | insert repo $repo) }
    let v = $empty | insert repo $repo | merge (open $f)
    if $v.repo != $repo {
        error make {msg: $"($f) belongs to ($v.repo), not ($repo); set XDG_STATE_HOME or rename one checkout"}
    }
    $v
}

def load-queue [repo: string]: nothing -> record {
    open-for $repo (queue-file $repo) {
        prs: []
        allow_optional: {}
    }
}

def save-queue [repo: string, q: record] {
    mkdir (state-dir $repo)
    $q | to json | save --force (queue-file $repo)
}

def load-state [repo: string]: nothing -> record {
    open-for $repo (state-file $repo) {
        asks: {}
        landed: []
        dropped: []
        not_this_pr: []
    }
    | default [] not_this_pr
}

def save-state [repo: string, st: record] {
    mkdir (state-dir $repo)
    $st | to json | save --force (state-file $repo)
}

# ── reading GitHub and herdr ──

const list_fields = "number,headRefOid,headRefName,baseRefName,mergeable,isDraft,statusCheckRollup"

# The open PRs, keyed by number.
def open-prs []: nothing -> record {
    let r = ^gh pr list --state open --limit 500 --json $list_fields | complete
    if $r.exit_code != 0 { error make {msg: $"gh pr list: ($r.stderr | str trim)"} }
    $r.stdout | from json | reduce --fold {} {|p, acc| $acc | insert ($p.number | into string) $p }
}

# Every remote branch tip, from one ls-remote rather than a GitHub API call.
def branch-tips []: nothing -> record {
    let r = ^git ls-remote origin "refs/heads/*" | complete
    if $r.exit_code != 0 { error make {msg: $"git ls-remote: ($r.stderr | str trim)"} }
    $r.stdout
    | lines
    | parse "{sha}\trefs/heads/{branch}"
    | reduce --fold {} {|t, acc| $acc | insert $t.branch $t.sha }
}

# What could change land.nu's verdict on a PR, without calling it.
def fingerprint [p: record, base_tip]: nothing -> string {
    let checks = $p.statusCheckRollup
    | each {|c| $"($c.name? | default $c.context?):($c.status? | default ''):($c.conclusion? | default $c.state?)" }
    | sort
    | str join ","
    [$p.headRefOid $base_tip $p.mergeable $p.isDraft $checks] | str join "|"
}

# Runs land.nu and returns its JSON record.
def land [
    pr: int
    agent
    dry: bool
    allow_optional: bool
]: nothing -> record {
    let args = [
        ($pr | into string)
    ]
    | append (if $agent != null { [--agent $agent] } else { [] })
    | append (if $dry { [--dry-run] } else { [] })
    | append (if $allow_optional { [--allow-optional] } else { [] })
    let r = ^$nu.current-exe $land_script ...$args | complete
    try {
        $r.stdout | lines | last | from json
    } catch {
        {
            result: error
            pr: $pr
            sha: null
            detail: $"land.nu printed no record: ($r.stderr | str trim)"
            next: "run land.nu by hand to see why"
        }
    }
}

# A queued PR that is no longer open: merged, or closed without a merge.
def gone-pr [pr: int]: nothing -> record {
    let r = ^gh pr view $pr --json state,url | complete
    if $r.exit_code != 0 { error make {msg: $"gh pr view ($pr): ($r.stderr | str trim)"} }
    let v = $r.stdout | from json
    match $v.state {
        MERGED => {
            result: merged
            pr: $pr
            sha: null
            detail: $"($v.url) is merged"
            next: ""
        }
        _ => {
            result: closed
            pr: $pr
            sha: null
            detail: $"($v.url) is ($v.state | str lowercase)"
            next: "remove it with `queue.nu remove`, or bring it to the user"
        }
    }
}

# ── one pass ──

# Reads every queued PR into the record queue-rules.nu decides on.
# `cache` maps a PR to `{key, at, verdict}` from earlier passes.
def snapshot [repo: string, st: record, cache: record]: nothing -> record {
    let q = load-queue $repo
    let order = $q.prs | where $it not-in $st.dropped
    let open = open-prs
    let open_branches = $open | values | get headRefName
    let tips = branch-tips
    mut cache = $cache
    mut items = []
    for n in $order {
        let key = $n | into string
        let p = $open | get -o $key
        let asks = $st.asks | get -o $key | default []
        if $p == null {
            $items = $items | append {pr: $n, verdict: (gone-pr $n), base: null, stacked: false, allow_optional: false, worker: null, worker_state: gone, asks: $asks}
            continue
        }
        # Stacked on a PR still open; a base no PR holds is the repository's
        # line of work, whether or not it is the default branch
        let stacked = $p.baseRefName in $open_branches
        let allow = ($q.allow_optional | get -o $key) == $p.headRefOid
        let worker = worker-of $repo $p.headRefName
        let ws = if $worker == null { "gone" } else { (worker-state $worker).state }
        # land.nu is the one judge of a PR; it is skipped only where its answer
        # cannot be used this pass, and reused while nothing it reads changed
        let verdict = if $stacked or $ws in [working busy blocked] {
            {result: skipped, sha: $p.headRefOid}
        } else {
            let fp = [
                (fingerprint $p ($tips | get -o $p.baseRefName))
                $allow
            ] | str join "|"
            let hit = $cache | get -o $key
            if $hit != null and $hit.key == $fp and ((date now) - $hit.at) < $verdict_ttl {
                $hit.verdict
            } else {
                let v = land $n $worker true $allow
                $cache = $cache | upsert $key {key: $fp, at: (date now), verdict: $v}
                $v
            }
        }
        let fix_asked = $asks | any {|a| $a.kind == "fix" and $a.sha == $verdict.sha }
        let said = if $verdict.result == ci-failed and $fix_asked and $ws == stopped {
            not-this-pr-of $worker $verdict.sha
        }
        $items = $items | append {pr: $n, verdict: $verdict, base: $p.baseRefName, stacked: $stacked, allow_optional: $allow, worker: $worker, worker_state: $ws, asks: $asks, said: $said}
    }
    {items: $items, cache: $cache}
}

# The prompt asking a worker to merge the base.
def merge-ask [base: string]: nothing -> string {
    $"This PR is next to land, and it conflicts with ($base) since other PRs landed. Merge origin/($base) into your branch \(no rebase, no force push\); where both sides made the same change, keep ($base)'s. Run the checks the repository asks for before a push, push, and end your turn with the PR URL."
}

# The prompt sending a CI failure back to its worker.
def fix-ask [v: record]: nothing -> string {
    let failed = $v.failed? | default [] | each {|f| $"($f.name) \(run ($f.run? | default '?')\): ($f.link)" } | str join "; "
    $"CI failed on ($v.sha | str substring 0..<7): ($failed). Read `gh run view <run> --log-failed` for each. If this PR, alone or merged with the base, caused it, fix the cause, push, and end your turn with the PR URL. If it is not this PR's \(a timeout on a loaded runner, a test that fails on code this PR does not touch\), do not push or rerun: end your turn with a line of its own that starts with ($not_this_pr_mark) and says why, naming the failing test. The queue then reruns the failed jobs once."
}

# The reason after `not_this_pr_mark` in the worker's reply to the fix ask for
# `sha`, or null. Only the reply is searched: the ask quotes the mark, and a
# wrapped line of it can start with the mark too.
def not-this-pr-of [agent: string, sha: string]: nothing -> oneof<string, nothing> {
    let r = ^herdr agent read $agent --source recent-unwrapped --lines 400 | complete
    if $r.exit_code != 0 { return null }
    $r.stdout | lines | not-this-pr-in $sha
}

# `not-this-pr-of` on a screen already read.
export def not-this-pr-in [sha: string]: list<string> -> oneof<string, nothing> {
    let screen = $in | enumerate
    let asked = $screen | where ($it.item | str starts-with $"❯ CI failed on ($sha | str substring 0..<7):") | last
    if $asked == null { return null }
    let reply = $screen | skip ($asked.index + 1) | skip until {|l| $l.item | str starts-with "⏺" }
    $reply
    | get item
    | each { str trim | str replace --regex '^⏺\s*' '' }
    | where ($it | str starts-with $not_this_pr_mark)
    | last
    | if $in == null { null } else {
        str substring ($not_this_pr_mark | str length).. | str trim
    }
}

# Sends `text` and waits only for its receipt. The ask is recorded before this
# runs, so a prompt that did not land shows up as no-progress, not as a loop.
def ask [agent: string, text: string]: nothing -> nothing {
    ^herdr agent prompt $agent $text --wait --until working --until blocked --timeout $prompt_timeout_ms | complete | ignore
}

# One pass in dry-run form: every PR's verdict and decision, nothing changed.
def dry-run [repo: string]: nothing -> record {
    if (setting-on $repo no-land) { return (no-land-result) }
    let st = load-state $repo
    let snap = snapshot $repo $st {}
    let d = decide $snap.items $st.not_this_pr
    {
        result: dry-run
        plan: (
            $snap.items | zip $d.actions | each {|z|
                {
                    pr: $z.0.pr
                    verdict: $z.0.verdict.result
                    worker: $z.0.worker
                    worker_state: $z.0.worker_state
                    action: $z.1.action
                    reason: $z.1.reason
                }
            }
        )
        stop: $d.stop
    }
}

def no-land-result []: nothing -> record {
    {result: manual-land, detail: "this repository has no-land: a person merges", next: "use land.nu per PR; it reports the CI verdict to pass on"}
}

# Passes over the queue until it is empty, the harness is needed, or `timeout`.
def run-queue [repo: string, interval: duration, timeout: duration]: nothing -> any {
    if (setting-on $repo no-land) { return (no-land-result) }
    let deadline = (date now) + $timeout
    mut cache = {}
    mut landed = []
    loop {
        mut st = load-state $repo
        let snap = snapshot $repo $st $cache
        $cache = $snap.cache
        if ($snap.items | is-empty) {
            return {
                result: done
                detail: "the queue is empty"
                next: "report the landings"
                landed: $landed
            }
        }
        let d = decide $snap.items $st.not_this_pr
        # A stop is returned after the pass's other actions: one worker waiting
        # on the harness holds up no other PR
        let by_pr = $snap.items | reduce --fold {} {|it, acc| $acc | insert ($it.pr | into string) $it }
        for a in $d.actions {
            let key = $a.pr | into string
            let item = $by_pr | get $key
            match $a.action {
                drop => {
                    $st = $st | update dropped { append $a.pr | uniq }
                }
                ask-merge | ask-fix => {
                    let kind = if $a.action == ask-merge { "merge" } else { "fix" }
                    $st = $st | upsert asks { upsert $key { default [] | append {kind: $kind, sha: $item.verdict.sha, at: (date now | format date "%+")} } }
                    save-state $repo $st
                    let base = $item.base
                    ask $item.worker (
                        if $kind == "merge" { merge-ask $base } else { fix-ask $item.verdict }
                    )
                    $cache = $cache | reject -o $key
                }
                rerun => {
                    # Recorded first, as for an ask: a rerun that fails to
                    # start shows up as `flaky`, not as a second rerun
                    let at = date now | format date "%+"
                    let sha = $item.verdict.sha
                    $st = $st
                    | upsert asks { upsert $key { default [] | append {kind: rerun, sha: $sha, at: $at} } }
                    | update not_this_pr {
                        append ($item.verdict.failed | each {|f| {check: $f.name, pr: $a.pr, sha: $sha, run: ($f.run? | default null), reason: $item.said, at: $at} })
                    }
                    save-state $repo $st
                    for run in $a.runs {
                        let r = ^gh run rerun $run --failed | complete
                        if $r.exit_code != 0 {
                            return {
                                result: rerun-failed
                                pr: $a.pr
                                agent: $item.worker
                                sha: $sha
                                detail: $"gh run rerun ($run) --failed: ($r.stderr | str trim)"
                                next: "rerun it by hand or bring it to the user, then run queue.nu again"
                                landed: $landed
                            }
                        }
                    }
                    $cache = $cache | reject -o $key
                }
            }
        }
        save-state $repo $st
        # Land at most one PR a pass: each landing moves the base under the rest
        let to_land = $d.actions | where action == land | get -o 0
        if $to_land != null {
            let item = $by_pr | get ($to_land.pr | into string)
            let r = land $to_land.pr $item.worker false $item.allow_optional
            $cache = $cache | reject -o ($to_land.pr | into string)
            match $r.result {
                landed => {
                    $landed = $landed | append $to_land.pr
                    $st = $st | update landed {
                        append (
                            {pr: $to_land.pr, sha: $r.sha, at: (date now | format date "%+")}
                            | merge ($r | select -o optional_failed cleanup_error)
                        )
                    } | update dropped { append $to_land.pr | uniq }
                    save-state $repo $st
                    # The next PR may land at once
                    if $d.stop == null { continue }
                }
                updated | pending | no-checks | unknown-mergeable | unknown | head-moved | conflict | ci-failed | would-update | merged => { }
                _ => {
                    return ($r | insert agent $item.worker | insert landed $landed)
                }
            }
        }
        if $d.stop != null {
            return ($d.stop | insert landed $landed)
        }
        if (date now) + $interval > $deadline {
            return {
                result: timeout
                detail: $"still running after ($timeout)"
                next: "run queue.nu again"
                landed: $landed
            }
        }
        sleep $interval
    }
}
