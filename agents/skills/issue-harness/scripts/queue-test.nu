#!/usr/bin/env nu
# Drives queue-rules.nu through the cases a real batch produced. Run it after
# changing the rules; it prints one line per case and exits 1 on a failure.

use std/assert
use queue-rules.nu [decide max_fix_asks max_merge_asks stuck_minutes not-this-pr-in]

# A queued PR with a stopped worker and no earlier asks.
def pr [n: int, result: string, --sha: string = "s1"]: nothing -> record {
    {
        pr: $n
        verdict: {
            result: $result
            sha: $sha
            detail: $"detail of ($n)"
            next: $"next of ($n)"
        }
        stacked: false
        worker: $"kn-($n)"
        worker_state: stopped
        asks: []
    }
}

# The action decided for each PR, as `{pr: action}` pairs in queue order.
def actions-of [d: record]: nothing -> list<string> {
    $d.actions | each {|a| $"($a.pr):($a.action)" }
}

const cases = [
    "only the head is asked to merge the base"
    "a CI failure is sent back and the next PR becomes the head"
    "behind the head, only a PR that needs no update lands"
    "a pending head still lets a clean PR behind it land"
    "a busy or working worker is passed over"
    "a blocked worker stops the queue"
    "a stacked PR waits for the PR under it"
    "a repeated ask on the same head stops the queue"
    "a new head after an ask is asked again"
    "send-backs and merges are capped"
    "an ask with no worker stops the queue"
    "merged PRs drop, closed PRs and forks stop"
    "an optional-only failure stops"
    "a worker merging the base keeps the head"
    "a queue nobody can move stops as stalled"
    "a failure the worker judged not its own is rerun once"
    "a check judged not their own on two PRs is flaky"
    "a head whose CI jobs no runner starts stops as no-runner"
    "a worker left busy for long stops the queue"
    "the worker's NOT-THIS-PR reply is read from a herdr screen"
    "the worker's NOT-THIS-PR reply is read through herdr-core's tag"
    "the worker's NOT-THIS-PR reply is read from a Codex screen"
    "the ask's own quote of the mark is not a reply"
]

def run-case [name: string] {
    match $name {
        "only the head is asked to merge the base" => {
            let d = decide [
                (pr 1 conflict)
                (pr 2 conflict)
                (pr 3 would-update)
            ]
            assert equal (actions-of $d) ["1:ask-merge" "2:skip" "3:skip"]
            assert equal $d.stop null
        }
        "a CI failure is sent back and the next PR becomes the head" => {
            let d = decide [
                (pr 1 ci-failed)
                (pr 2 would-update)
                (pr 3 conflict)
            ]
            assert equal (actions-of $d) ["1:ask-fix" "2:land" "3:skip"]
        }
        "behind the head, only a PR that needs no update lands" => {
            let d = decide [
                (pr 1 would-update)
                (pr 2 would-update)
                (pr 3 would-merge)
            ]
            assert equal (actions-of $d) ["1:land" "2:skip" "3:land"]
        }
        "a pending head still lets a clean PR behind it land" => {
            let d = decide [
                (pr 1 pending)
                (pr 2 would-merge)
                (pr 3 conflict)
            ]
            assert equal (actions-of $d) ["1:wait" "2:land" "3:skip"]
        }
        "a busy or working worker is passed over" => {
            let d = decide [
                (pr 1 conflict | update worker_state busy)
                (pr 2 conflict | update worker_state working)
                (pr 3 conflict)
            ]
            assert equal (actions-of $d) ["1:skip" "2:skip" "3:ask-merge"]
        }
        "a blocked worker stops the queue" => {
            let d = decide [
                (pr 1 would-merge)
                (pr 2 pending | update worker_state blocked)
            ]
            assert equal $d.stop.result blocked
            assert equal $d.stop.pr 2
            assert equal $d.stop.agent kn-2
        }
        "a stacked PR waits for the PR under it" => {
            let d = decide [
                (pr 1 would-update | update stacked true)
                (pr 2 conflict)
            ]
            assert equal (actions-of $d) ["1:skip" "2:ask-merge"]
        }
        "a repeated ask on the same head stops the queue" => {
            let fix = decide [
                (pr 1 ci-failed | update asks [
                    {kind: fix, sha: s1}
                ])
            ]
            assert equal $fix.stop.result no-progress
            let merge = decide [
                (pr 1 conflict | update asks [
                    {kind: merge, sha: s1}
                ])
            ]
            assert equal $merge.stop.result no-progress
        }
        "a new head after an ask is asked again" => {
            let d = decide [
                (pr 1 ci-failed --sha s2 | update asks [
                    {kind: fix, sha: s1}
                ])
            ]
            assert equal (actions-of $d) ["1:ask-fix"]
            assert equal $d.stop null
        }
        "send-backs and merges are capped" => {
            let fixes = 1..$max_fix_asks | each {|i| {kind: fix, sha: $"old($i)"} }
            assert equal (decide [
                (pr 1 ci-failed | update asks $fixes)
            ]).stop.result send-back-limit
            let merges = 1..$max_merge_asks | each {|i| {kind: merge, sha: $"old($i)"} }
            assert equal (decide [
                (pr 1 conflict | update asks $merges)
            ]).stop.result conflict-limit
        }
        "an ask with no worker stops the queue" => {
            let d = decide [
                (pr 1 conflict | update worker null | update worker_state gone)
            ]
            assert equal $d.stop.result no-worker
            # Landing needs no worker
            let l = decide [
                (pr 1 would-merge | update worker null | update worker_state gone)
            ]
            assert equal (actions-of $l) ["1:land"]
        }
        "merged PRs drop, closed PRs and forks stop" => {
            # A merged PR's worker is gone or blocked; neither matters
            let d = decide [
                (pr 1 merged | update worker_state blocked)
                (pr 2 would-merge)
            ]
            assert equal (actions-of $d) ["1:drop" "2:land"]
            assert equal (decide [
                (pr 1 closed)
            ]).stop.result closed
            assert equal (decide [
                (pr 1 fork)
            ]).stop.result fork
        }
        "an optional-only failure stops" => {
            assert equal (decide [
                (pr 1 optional-failed)
            ]).stop.result optional-failed
        }
        "a worker merging the base keeps the head" => {
            let d = decide [
                (
                    pr 1 skipped
                    | update worker_state working
                    | update asks [
                        {kind: merge, sha: s1}
                    ]
                )
                (pr 2 conflict)
            ]
            assert equal (actions-of $d) ["1:skip" "2:skip"]
            # A worker busy on a CI fix does not
            let f = decide [
                (
                    pr 1 skipped
                    | update worker_state working
                    | update asks [
                        {kind: fix, sha: s1}
                    ]
                )
                (pr 2 conflict)
            ]
            assert equal (actions-of $f) ["1:skip" "2:ask-merge"]
        }
        "a queue nobody can move stops as stalled" => {
            let d = decide [
                (pr 1 would-update | update stacked true)
                (pr 2 draft)
            ]
            assert equal $d.stop.result stalled
            # A worker at work will move something; no stop
            let w = decide [
                (pr 1 would-update | update stacked true)
                (pr 2 skipped | update worker_state busy)
            ]
            assert equal $w.stop null
            # A PR merged outside the queue drops; the next pass finds it empty
            assert equal (decide [
                (pr 1 merged)
            ]).stop null
        }
        "a failure the worker judged not its own is rerun once" => {
            let judged = pr 1 ci-failed
            | update verdict { insert failed [{name: e2e, run: "9"}] }
            | update asks [
                {kind: fix, sha: s1}
            ]
            | insert said "ENOTEMPTY in cleanup"
            let d = decide [$judged]
            assert equal (actions-of $d) ["1:rerun"]
            assert equal ($d.actions.0.runs) ["9"]
            assert equal $d.stop null
            # Failing again on the same head is not rerun a second time
            let again = decide [
                ($judged | update asks { append {kind: rerun, sha: s1} })
            ]
            assert equal $again.stop.result flaky
            assert equal $again.stop.checks [e2e]
        }
        "a check judged not their own on two PRs is flaky" => {
            let judged = pr 2 ci-failed
            | update verdict { insert failed [{name: e2e, run: "12"}] }
            | update asks [
                {kind: fix, sha: s1}
            ]
            | insert said "timeout"
            let d = decide [$judged] [
                {
                    check: e2e
                    pr: 1
                    sha: s0
                    run: "9"
                    reason: "ENOTEMPTY"
                }
            ]
            # The rerun still goes ahead; the harness files the flake meanwhile
            assert equal (actions-of $d) ["2:rerun"]
            assert equal $d.stop.result flaky
            # The PR's own earlier failure does not count
            let own = decide [$judged] [
                {
                    check: e2e
                    pr: 2
                    sha: s0
                    run: "8"
                    reason: "x"
                }
            ]
            assert equal $own.stop null
        }
        "a head whose CI jobs no runner starts stops as no-runner" => {
            let short = decide [
                (
                    pr 1 pending
                    | insert stuck {kind: queued, minutes: ($stuck_minutes - 1)}
                )
            ]
            assert equal (actions-of $short) ["1:wait"]
            assert equal $short.stop null
            let long = decide [
                (
                    pr 1 pending
                    | insert stuck {kind: queued, minutes: $stuck_minutes}
                )
            ]
            assert equal $long.stop.result no-runner
            # Running jobs are CI taking its time, not a missing runner
            let running = decide [
                (pr 1 pending | insert stuck null)
            ]
            assert equal $running.stop null
        }
        "a worker left busy for long stops the queue" => {
            let busy = {|minutes: int|
                pr 1 skipped | update worker_state busy | insert stuck {kind: busy, minutes: $minutes}
            }
            let short = decide [
                (do $busy ($stuck_minutes - 1))
                (pr 2 would-merge)
            ]
            assert equal (actions-of $short) ["1:skip" "2:land"]
            assert equal $short.stop null
            let long = decide [
                (do $busy $stuck_minutes)
                (pr 2 would-merge)
            ]
            assert equal $long.stop.result busy
            # The PR behind it still lands this pass
            assert equal (actions-of $long) ["1:stop" "2:land"]
        }
        "the worker's NOT-THIS-PR reply is read from a herdr screen" => {
            let screen = [
                "❯ CI failed on abc1234: e2e (run 9): https://x. If it is not this PR's, end"
                "  with a line of its own that starts with NOT-THIS-PR: and says why."
                "⏺ Reading the log."
                "⏺ NOT-THIS-PR: e2e timed out on a loaded runner"
            ]
            assert equal ($screen | not-this-pr-in abc1234def) "e2e timed out on a loaded runner"
        }
        "the worker's NOT-THIS-PR reply is read through herdr-core's tag" => {
            let screen = [
                '❯ <hc from="t4b">CI failed on abc1234: e2e (run 9): https://x'
                "⏺ NOT-THIS-PR: story timing out on code this PR does not touch"
            ]
            assert equal ($screen | not-this-pr-in abc1234def) "story timing out on code this PR does not touch"
        }
        "the worker's NOT-THIS-PR reply is read from a Codex screen" => {
            let screen = [
                '› <hc from="t4b">CI failed on abc1234: e2e (run 9): https://x'
                "• NOT-THIS-PR: flaky teardown"
            ]
            assert equal ($screen | not-this-pr-in abc1234def) "flaky teardown"
        }
        "the ask's own quote of the mark is not a reply" => {
            let screen = [
                "❯ CI failed on abc1234: e2e (run 9). End with a line that starts with"
                "NOT-THIS-PR: and says why."
            ]
            assert equal ($screen | not-this-pr-in abc1234def) null
            # An ask for an older head is not this head's
            let older = [
                "❯ CI failed on 0000000: e2e"
                "⏺ NOT-THIS-PR: old"
            ]
            assert equal ($older | not-this-pr-in abc1234def) null
        }
    }
}

def main [] {
    let results = $cases | each {|c|
        let r = try { run-case $c; null } catch {|e| $e.msg }
        print $"(if $r == null { 'ok  ' } else { 'FAIL' }) ($c)(if $r != null { $': ($r)' } else { '' })"
        $r
    }
    if ($results | any {|r| $r != null }) { exit 1 }
}
