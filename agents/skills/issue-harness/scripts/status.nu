#!/usr/bin/env nu
# One snapshot of a repository's harness for something to show: the workers
# and their PRs, the landing queue, what landed, and every open spec's
# tickets. herdr-app's harness panel runs this and draws what it prints, so
# what counts as blocked, queued or ready is decided here, by the same
# functions the scripts act on, and not a second time in the panel.

use harness.nu [state-dir main-checkout worker-state current-mux agents-in]
use spec.nu [status]

# How many landings to show, newest first.
const landed_shown = 5

# Print the snapshot of the repository holding `dir` as one JSON line.
#
# Changes nothing. A part that cannot be read (GitHub unreachable, herdr not
# running) is left empty and named in `errors`, so the rest still shows.
#
# @example
# status.nu --dir ~/ghq/github.com/me/app
def main [
    --dir: string  # any checkout of the repository; default: here
    --mux: string  # whose workers: `hc` or `herdr`; default: where this runs
] {
    if $dir != null { cd $dir }
    let repo = main-checkout
    cd $repo
    let state = state-dir $repo

    let prs = attempt "gh pr list" { open-prs }
    let mux = $mux | default (current-mux)
    let workers = attempt "workers" { workers $repo $mux ($prs.value | default []) }
    let specs = attempt "specs" { open-specs $state }
    let merged = attempt "gh pr list --state merged" { merged-prs }
    let queue = queue $state $mux ($prs.value | default []) ($merged.value | default [])

    let errors = [$prs $merged $workers $specs] | where error != null | get error
    {
        repo: $repo
        name: ($repo | path basename)
        at: (date now | format date "%+")
        attention: (
            (attention
                ($workers.value | default [])
                ($specs.value | default [])
                ($queue.queue | get number)
            )
        )
        workers: ($workers.value | default [])
        queue: $queue.queue
        landed: $queue.landed
        specs: ($specs.value | default [])
        errors: $errors
    } | to json --raw | print
}

# Runs `body`, returning `{value}` or, when it fails, `{value: null, error}`
# labelled with `what`.
def attempt [what: string, body: closure]: nothing -> record {
    try {
        {
            value: (do $body)
            error: null
        }
    } catch {|e| {
        value: null
        error: $"($what): ($e.msg)"
    } }
}

# ── GitHub ──

def open-prs []: nothing -> list<record> {
    let r = ^gh pr list --state open --limit 100 --json number,title,headRefName,isDraft,url,statusCheckRollup | complete
    if $r.exit_code != 0 {
        error make {
            msg: ($r.stderr | str trim)
        }
    }
    $r.stdout | from json | each {|p|
        {
            number: $p.number
            title: $p.title
            branch: $p.headRefName
            draft: $p.isDraft
            url: $p.url
            ci: (ci-of $p.statusCheckRollup)
        }
    }
}

# Folds a PR's checks into one word: `failing` when any failed, `pending`
# while any runs, `passing` when all passed, `none` with no checks at all.
# Check runs report a conclusion, commit statuses a state.
#
# @example
# ci-of [{status: COMPLETED, conclusion: SUCCESS}, {state: PENDING}]   # => pending
def ci-of [checks: list<any>]: nothing -> string {
    if ($checks | is-empty) { return "none" }
    let bad = [
        FAILURE
        TIMED_OUT
        CANCELLED
        ACTION_REQUIRED
        STARTUP_FAILURE
        ERROR
    ]
    let failed = $checks | any {|c| ($c.conclusion? | default "") in $bad or ($c.state? | default "") in $bad }
    if $failed { return "failing" }
    let running = $checks | any {|c|
        (($c.status? != null) and $c.status != "COMPLETED") or (($c.state? | default "") in [PENDING EXPECTED])
    }
    if $running { "pending" } else { "passing" }
}

# ── workers ──

# Every linked worktree on an `issue-…` branch that an agent in `mux` works
# in, with that agent's state. A worktree whose worker runs in the other
# multiplexer belongs to the harness there and is left out, as is one with no
# agent at all. A spec's integration worktree (`spec-…`) is not a worker's and
# shows under its spec instead.
def workers [repo: string, mux: string, prs: list<record>]: nothing -> list<record> {
    let trees = ^git -C $repo worktree list --porcelain
    | split row "\n\n"
    | where $it != ""
    | each { lines | parse "{key} {value}" | transpose -r -d }
    | where ($it.branch? | default "" | str starts-with "refs/heads/issue-")
    | each {|w| {path: $w.worktree, branch: ($w.branch | str replace "refs/heads/" "")} }
    let agents = agents-in $mux
    $trees | each {|w|
        let agent = $agents
        | where $it.cwd == $w.path or ($it.cwd | str starts-with $"($w.path)/")
        | get -o 0.name
        if $agent == null { return null }
        let ticket = $w.branch | parse --regex '^issue-(?<n>\d+)' | get -o 0.n
        {
            name: $agent
            branch: $w.branch
            worktree: $w.path
            ticket: (if $ticket == null { null } else { $ticket | into int }), 
            state: (worker-state $agent --mux $mux).state
            pr: ($prs | where branch == $w.branch | get -o 0)
        }
    } | compact
}

# ── queue ──

# What queue.nu would land, in its file's order, and the latest landings,
# each limited to what `mux`'s harness queued. A PR queued before queue.nu
# recorded that has no entry, and was queued from the herdr TUI.
def queue [
    state: string
    mux: string
    prs: list<record>
    merged: list<record>
]: nothing -> record {
    let q = open-or ($state | path join queue.json) {
        prs: []
        mux: {}
    }
    let st = open-or ($state | path join queue-state.json) {
        landed: []
        dropped: []
    }
    let dropped = $st.dropped? | default []
    let queued_from = {|n|
        $q.mux | get -o ($n | into string) | default "herdr"
    }
    {
        queue: (
            $q.prs
            | where $it not-in $dropped and (do $queued_from $it) == $mux
            | each {|n| $prs | where number == $n | get -o 0 | default { number: $n } }
        )
        landed: (
            $st.landed?
            | default []
            | where ($it.mux? | default "herdr") == $mux
            | reverse
            | first $landed_shown
            | each {|l|
                let pr = $merged | where number == $l.pr | get -o 0
                {pr: $l.pr, at: $l.at, title: $pr.title?, url: $pr.url?}
            }
        )
    }
}

# The latest merged PRs, for the titles of what landed.
def merged-prs []: nothing -> list<record> {
    let r = ^gh pr list --state merged --limit 50 --json number,title,url | complete
    if $r.exit_code != 0 {
        error make {
            msg: ($r.stderr | str trim)
        }
    }
    $r.stdout | from json
}

def open-or [f: string, empty: record]: nothing -> record {
    if ($f | path exists) {
        $empty | merge (open $f)
    } else { $empty }
}

# ── specs ──

# spec.nu's frontier for every spec started here whose issue is still open.
def open-specs [state: string]: nothing -> list<record> {
    if not ($state | path exists) { return [] }
    ls $state
    | where name =~ 'spec-\d+\.json$'
    | get name
    | each { path basename | parse --regex 'spec-(?<n>\d+)\.json' | get 0.n | into int }
    | each {|n| status $n }
    | where state == "OPEN"
    | select spec title branch result ready running waiting integrated done
}

# ── what needs the person ──

# The workers waiting on an answer and the specs that cannot move, most
# urgent first. A worker that stopped on a PR the queue already holds is the
# queue's to wake: queue.nu asks it for merges and fixes itself.
def attention [workers: list<record>, specs: list<record>, queued: list<int>]: nothing -> list<record> {
    let blocked = $workers | where state == blocked | each {|w| {kind: blocked, worker: $w.name, detail: "permission prompt or dialog"} }
    let stopped = $workers
    | where state == stopped and ($it.pr == null or $it.pr.number not-in $queued)
    | each {|w|
        let detail = if $w.pr == null { "turn ended: a question, or stuck" } else { $"turn ended with PR #($w.pr.number)" }
        {kind: stopped, worker: $w.name, detail: $detail}
    }
    let stuck = $specs | where result == stuck | each {|s| {kind: stuck, spec: $s.spec, detail: "no ticket can start and none is under way"} }
    $blocked | append $stopped | append $stuck
}
