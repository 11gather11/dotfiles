#!/usr/bin/env nu
# A spec's tickets on one integration branch: workers branch from it,
# integrate.nu merges each ticket back after a local check, and the branch
# reaches the base as one PR, so CI runs once per spec. This file reads the
# ticket graph from GitHub and keeps the spec's state; spec-rules.nu decides
# which tickets can start.

use harness.nu [state-dir main-checkout heavy-check]
use spec-rules.nu [frontier]

# Start a spec: create its integration branch and list the tickets that can
# start.
#
# Prints one JSON line last, as every subcommand does. Exit status: 0 done
# as asked; 2 the harness has to act; 1 error.
#
# @example
# spec.nu start 412
def "main start" [spec: int] {
    respond { start $spec }
}

# The tickets that can start now, those waiting, and those under way.
def "main frontier" [spec: int] {
    respond { status $spec }
}

# After every ticket is in and the review fixes too: merge the base into the
# integration branch and run the check there, ready for the gate's review.
def "main finish" [spec: int] {
    respond { finish $spec }
}

# Push the integration branch once the gate's review covers its head, and
# hand back what the PR needs.
def "main push" [spec: int] {
    respond { push $spec }
}

def main [] {
    {result: error, detail: "usage: spec.nu start|frontier|finish|push <spec>"} | to json --raw | print
    exit 1
}

def respond [body: closure] {
    let out = try { do $body } catch {|e| {result: error, detail: $e.msg, next: "fix the cause, then run the same command again"} }
    $out | to json --raw | print
    exit (match $out.result {
        started | frontier | integrated | finished | pushed => 0
        error => 1
        _ => 2
    })
}

# ── state ──

export def spec-file [repo: string, spec: int]: nothing -> string {
    state-dir $repo | path join $"spec-($spec).json"
}

export def load-spec [repo: string, spec: int]: nothing -> record {
    let f = spec-file $repo $spec
    if not ($f | path exists) { error make {msg: $"spec #($spec) was not started here: run `spec.nu start ($spec)`"} }
    open $f
}

export def save-spec [repo: string, s: record] {
    mkdir (state-dir $repo)
    $s | to json | save --force (spec-file $repo $s.spec)
}

# ── GitHub ──

const graph_query = 'query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      number title state
      subIssues(first: 100) { nodes {
        number title state body
        blockedBy(first: 50) { nodes { number state } }
      } }
    }
  }
}'

# The spec and its tickets. A ticket's blockers are GitHub's own blocked-by
# links, or, where /to-tickets could not set them, the issues its "Blocked
# by" section names.
export def read-graph [spec: int]: nothing -> record {
    let r = ^gh api graphql -F "owner={owner}" -F "repo={repo}" -F $"n=($spec)" -f $"query=($graph_query)" | complete
    if $r.exit_code != 0 { error make {msg: $"reading spec #($spec): ($r.stderr | str trim)"} }
    let issue = $r.stdout | from json | get data.repository.issue
    if $issue == null { error make {msg: $"#($spec) is not an issue of this repository"} }
    let tickets = $issue.subIssues.nodes | each {|t|
        let linked = $t.blockedBy.nodes
        let blocked_by = if ($linked | is-not-empty) { $linked } else { blockers-in-body $t.body }
        {number: $t.number, title: $t.title, state: $t.state, blocked_by: $blocked_by}
    }
    if ($tickets | is-empty) {
        error make {msg: $"#($spec) has no sub-issues: split it with /to-tickets first"}
    }
    {
        spec: $issue.number
        title: $issue.title
        state: $issue.state
        tickets: $tickets
    }
}

# Issues named under a "Blocked by" heading, with their state.
def blockers-in-body [body: string]: nothing -> list<record> {
    let section = $body
    | split row "\n## "
    | where ($it | str lowercase | str starts-with "blocked by")
    | get -o 0
    | default ""
    $section
    | parse --regex '#(?<n>\d+)'
    | get n
    | uniq
    | each {|n|
        let v = ^gh issue view $n --json number,state | complete
        if $v.exit_code != 0 { error make {msg: $"gh issue view ($n), a blocker named in the body: ($v.stderr | str trim)"} }
        $v.stdout | from json
    }
}

def default-branch []: nothing -> string {
    ^gh repo view --json defaultBranchRef --jq .defaultBranchRef.name | str trim
}

# ── git ──

export def git-out [dir: string, args: list<string>]: nothing -> string {
    let r = ^git -C $dir ...$args | complete
    if $r.exit_code != 0 { error make {msg: $"git ($args | str join ' '): ($r.stderr | str trim)"} }
    $r.stdout | str trim
}

# Ticket numbers that already have a local `issue-<n>-…` branch: a worker
# took them, whether or not it is still running.
export def taken-tickets [repo: string]: nothing -> list<int> {
    git-out $repo [branch --format "%(refname:short)"]
    | lines
    | parse --regex '^issue-(?<n>\d+)(?:-|$)'
    | get n
    | each { into int }
}

# ── subcommands ──

def start [spec: int]: nothing -> record {
    let repo = main-checkout
    cd $repo
    let f = spec-file $repo $spec
    if ($f | path exists) { return (status $spec) }
    let graph = read-graph $spec
    let base = default-branch
    let branch = $"spec-($spec)"
    git-out $repo [fetch --quiet origin $base] | ignore
    # wt's hooks prepare the checkout as for any worktree (direnv, local
    # files) and open a herdr workspace, where the integration branch can be
    # looked at
    let r = ^wt -C $repo switch --create $branch --base $"origin/($base)" --no-cd | complete
    if $r.exit_code != 0 { error make {msg: $"wt switch --create ($branch): ($r.stderr | str trim)"} }
    let worktree = git-out $repo [worktree list --porcelain]
    | split row "\n\n"
    | where ($it | str contains $"branch refs/heads/($branch)")
    | first
    | lines
    | first
    | str replace "worktree " ""
    save-spec $repo {
        spec: $spec
        title: $graph.title
        base: $base
        branch: $branch
        worktree: $worktree
        integrated: []
    }
    status $spec | update result started
}

def status [spec: int]: nothing -> record {
    let repo = main-checkout
    cd $repo
    let s = load-spec $repo $spec
    let graph = read-graph $spec
    let integrated = $s.integrated | each { $in.ticket } | compact
    let f = frontier $graph.tickets $integrated (taken-tickets $repo)
    let titles = $graph.tickets | reduce --fold {} {|t, acc| $acc | insert ($t.number | into string) $t.title }
    let ready = $f.ready | each {|n| {ticket: $n, title: ($titles | get ($n | into string)), branch: $"issue-($n)"} }
    {
        result: (if $f.stuck { "stuck" } else { "frontier" })
        spec: $spec
        branch: $s.branch
        worktree: $s.worktree
        ready: $ready
        running: $f.running
        waiting: $f.waiting
        integrated: $integrated
        done: $f.done
        next: (
            if $f.stuck {
                $"no ticket can start and none is under way: a cycle among the blockers, or one outside the spec still open \(($f.waiting | to nuon)\). Bring it to the user"
            } else if $f.done {
                $"every ticket is in: review the integration branch \(review.nu --base ($s.base) ($spec) ($integrated | str join ' ') in ($s.worktree)\), have the fixes made and integrated, then spec.nu finish ($spec)"
            } else if ($ready | is-empty) {
                "wait for the running workers; integrate each one that stops with DONE"
            } else {
                $"start a worker per ready ticket: spawn.nu <prefix>-<n> issue-<n>-<slug> \"Implement ticket #<n> of spec #($spec) with the tdd skill.\" --spec ($spec)"
            }
        )
    }
}

def finish [spec: int]: nothing -> record {
    let repo = main-checkout
    cd $repo
    let s = load-spec $repo $spec
    let st = status $spec
    if not $st.done {
        return (
            $st
            | update result not-done
            | update next "integrate the remaining tickets first"
        )
    }
    let wt = $s.worktree
    let dirty = git-out $wt [status --porcelain]
    if $dirty != "" { error make {msg: $"($wt) has uncommitted changes; the integration worktree takes merges only"} }
    git-out $wt [fetch --quiet origin $s.base] | ignore
    # Lines that merge cleanly can still disagree in meaning; the check below
    # is what catches that before the one CI run
    let m = ^git -C $wt merge --no-edit $"origin/($s.base)" | complete
    if $m.exit_code != 0 {
        ^git -C $wt merge --abort | complete | ignore
        return {
            result: base-conflict
            spec: $spec
            detail: $"origin/($s.base) conflicts with ($s.branch)"
            next: $"start a worker with --spec ($spec) to merge origin/($s.base) into its branch and resolve it, integrate it, then spec.nu finish ($spec) again"
        }
    }
    let check = heavy-check $repo $wt $"spec-($spec)"
    if not $check.ok {
        return {
            result: check-failed
            spec: $spec
            detail: $check.detail
            log: $check.log
            next: $"start a worker with --spec ($spec) to fix it from the log, integrate it, then spec.nu finish ($spec) again"
        }
    }
    {
        result: finished
        spec: $spec
        head: (git-out $wt [rev-parse HEAD])
        worktree: $wt
        next: $"in ($wt): codex-review-run --base ($s.base) \(the PR gate; fix and integrate anything it finds, then finish again\), then spec.nu push ($spec)"
    }
}

def push [spec: int]: nothing -> record {
    let repo = main-checkout
    cd $repo
    let s = load-spec $repo $spec
    let wt = $s.worktree
    git-out $wt [push --quiet -u origin $s.branch] | ignore
    let closes = [$spec] | append ($s.integrated | each { $in.ticket } | compact) | each {|n| $"Closes #($n)" } | str join "\n"
    let decisions = $s.integrated | each {|i| git-out $wt [log -1 --format=%B $i.sha] | str trim | $"(if $i.ticket != null { $'#($i.ticket)' } else { $i.branch }):\n($in)" } | str join "\n\n"
    {
        result: pushed
        spec: $spec
        branch: $s.branch
        closes: $closes
        tickets: ($s.integrated | each { $in.ticket } | compact)
        last_commits: $decisions
        next: $"from ($wt): gh pr create --base ($s.base) --head ($s.branch), the body in the repository's PR format with each ticket's Decisions and Deferred \(from last_commits\) and ending with `closes`; file the Deferred items as issues; then queue.nu add <pr>"
    }
}
