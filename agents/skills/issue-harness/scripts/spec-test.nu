#!/usr/bin/env nu
# Drives spec-rules.nu through the shapes a ticket graph takes. Prints one line
# per case and exits 1 on a failure.

use std/assert
use spec-rules.nu [frontier]

def t [
    n: int
    --state: string = "OPEN"
    --outside: list<int> = []
    --closed: list<int> = []
    ...on: int
]: nothing -> record {
    {
        number: $n
        title: $"ticket ($n)"
        state: $state
        blocked_by: (
            ($on | each {|b| {number: $b, state: "OPEN"} })
            | append ($outside | each {|b| {number: $b, state: "OPEN"} })
            | append ($closed | each {|b| {number: $b, state: "CLOSED"} })
        )
    }
}

const cases = [
    "tickets without blockers start at once"
    "a ticket waits until its blocker is integrated"
    "a running ticket is not offered again"
    "a blocker outside the spec counts once closed"
    "every ticket integrated is done"
    "a cycle is stuck"
    "a closed ticket is not offered"
]

def run-case [name: string] {
    match $name {
        "tickets without blockers start at once" => {
            let f = frontier [
                (t 1)
                (t 2)
                (t 3 1)
            ] [] []
            assert equal $f.ready [1 2]
            assert equal $f.waiting [
                {
                    number: 3
                    on: [1]
                }
            ]
            assert equal $f.done false
        }
        "a ticket waits until its blocker is integrated" => {
            assert equal (frontier [
                (t 1)
                (t 2 1)
            ] [] [1]).ready []
            assert equal (frontier [
                (t 1)
                (t 2 1)
            ] [1] []).ready [2]
        }
        "a running ticket is not offered again" => {
            let f = frontier [
                (t 1)
                (t 2)
            ] [] [1]
            assert equal $f.ready [2]
            assert equal $f.running [1]
        }
        "a blocker outside the spec counts once closed" => {
            assert equal (frontier [
                (t 1 --outside [90])
            ] [] []).ready []
            assert equal (frontier [
                (t 1 --closed [90])
            ] [] []).ready [1]
        }
        "every ticket integrated is done" => {
            let f = frontier [
                (t 1)
                (t 2 1)
            ] [1 2] []
            assert equal $f.done true
            assert equal $f.stuck false
        }
        "a cycle is stuck" => {
            let f = frontier [
                (t 1 2)
                (t 2 1)
            ] [] []
            assert equal $f.stuck true
            # Something under way may still unblock the rest
            assert equal (frontier [
                (t 1)
                (t 2 3)
                (t 3 2)
            ] [] [1]).stuck false
        }
        "a closed ticket is not offered" => {
            let f = frontier [
                (t 1 --state CLOSED)
                (t 2 --closed [1])
            ] [] []
            # Closed outside the flow, it no longer holds the ticket after it
            assert equal $f.ready [2]
            assert equal $f.done false
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
