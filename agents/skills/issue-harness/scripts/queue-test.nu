#!/usr/bin/env nu
# Drives queue-rules.nu through the cases a real batch produced. Run it after
# changing the rules; it prints one line per case and exits 1 on a failure.

use std/assert
use queue-rules.nu [decide max_fix_asks max_merge_asks]

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
