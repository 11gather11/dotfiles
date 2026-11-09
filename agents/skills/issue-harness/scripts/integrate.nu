#!/usr/bin/env nu
# Merges one finished branch into a spec's integration branch. With no CI per
# ticket, this is where a ticket is checked: the commit is pinned, the
# repository's integration check runs on it, and only that commit is merged.

use harness.nu [main-checkout worker-of worker-state heavy-check]
use spec.nu [load-spec save-spec git-out taken-tickets read-graph]
use spec-rules.nu [frontier]

const prompt_timeout_ms = "30000"

# Integrate `branch` (a ticket's `issue-<n>-…`, or a fix branch) into spec
# `spec`'s integration branch.
#
# Prints one JSON line last: `integrated` with the tickets that can start now;
# otherwise what stopped it. `behind`, `dirty` and `check-failed` have
# already been sent to the worker, so wait on it and run this again when it
# stops. Exit status: 0 integrated; 2 the harness has to act; 1 error.
#
# @example
# integrate.nu 412 issue-415-export
def main [spec: int, branch: string] {
    let out = try { integrate $spec $branch } catch {|e| {result: error, detail: $e.msg, next: "fix the cause, then run integrate.nu again"} }
    $out | to json --raw | print
    exit (match $out.result {
        integrated => 0
        error => 1
        _ => 2
    })
}

def integrate [spec: int, branch: string]: nothing -> record {
    let repo = main-checkout
    cd $repo
    let s = load-spec $repo $spec
    let ticket = $branch | parse --regex '^issue-(?<n>\d+)(?:-|$)' | get -o 0.n | if $in == null { null } else { into int }
    if $ticket != null and $ticket in ($s.integrated | each { $in.ticket } | compact) {
        return {
            result: error
            detail: $"#($ticket) is already in ($s.branch)"
            next: "nothing to do"
        }
    }
    let path = worktree-path $repo $branch
    if $path == null { error make {msg: $"($branch) has no worktree"} }

    let worker = worker-of $repo $branch
    let ws = if $worker == null { "gone" } else { (worker-state $worker).state }
    if $ws in [working busy blocked] {
        return {
            result: $ws
            worker: $worker
            detail: $"($worker) is ($ws)"
            next: "wait for it to stop, then integrate.nu again"
        }
    }
    let say = {|result: string, detail: string, prompt: string|
        if $worker != null { ask $worker $prompt }
        {
            result: $result
            branch: $branch
            worker: $worker
            detail: $detail
            next: (
                if $worker != null { $"asked ($worker); wait for it to stop, then integrate.nu again" } else { $"no worker holds ($branch): start one on it with --spec and this prompt: ($prompt)" }
            )
        }
    }

    if (git-out $path [status --porcelain]) != "" {
        return (
            (do
                $say
                dirty
                $"($path) has uncommitted changes"
                "Commit everything that belongs to this ticket, then end your turn with DONE."
            )
        )
    }
    let sha = git-out $repo [rev-parse $branch]
    let tip = git-out $repo [rev-parse $s.branch]
    # The worker merges the integration tip itself, where it has the context
    # to resolve a conflict; the merge below then cannot conflict
    let has_tip = (^git -C $repo merge-base --is-ancestor $tip $sha | complete).exit_code == 0
    if not $has_tip {
        return (
            (do
                $say
                behind
                $"($branch) does not contain ($s.branch) at ($tip | str substring 0..<7)"
                $"Other tickets were integrated. Merge the local branch ($s.branch) \(not origin\) into yours, resolve any conflict, run the checks, commit, and end your turn with DONE."
            )
        )
    }

    let label = $"spec-($spec)-($branch)"
    let check = heavy-check $repo $path $label
    if not $check.ok {
        return (
            do $say check-failed $check.detail $"The integration check failed on ($sha | str substring 0..<7); the output is in ($check.log). Fix the cause, commit, and end your turn with DONE."
            | insert log $check.log
        )
    }
    # Only the commit that was checked goes in
    if (git-out $repo [rev-parse $branch]) != $sha {
        return {
            result: head-moved
            branch: $branch
            detail: $"($branch) moved during the check"
            next: "integrate.nu again"
        }
    }
    let title = if $ticket != null {
        read-graph $spec | get tickets | where number == $ticket | get -o 0.title | default $branch
    } else { $branch }
    let subject = if $ticket != null { $"Merge #($ticket): ($title)" } else { $"Merge ($branch)" }
    git-out $s.worktree [merge --no-ff -m $subject $sha] | ignore
    let merge = git-out $s.worktree [rev-parse HEAD]
    let s = $s | update integrated { append {ticket: $ticket, branch: $branch, sha: $sha, merge: $merge} }
    save-spec $repo $s

    # The branch stays until the spec lands: the merge points at it, and it is
    # the only copy of the work outside this Mac's integration branch. wt's
    # remove hook closes the worker's herdr workspace.
    let rm = ^wt -C $repo remove --no-delete-branch --format=json $path | complete
    let graph = read-graph $spec
    let f = frontier $graph.tickets ($s.integrated | each { $in.ticket } | compact) (
        taken-tickets $repo
        | where $it not-in ($s.integrated | each { $in.ticket } | compact)
    )
    {
        result: integrated
        branch: $branch
        ticket: $ticket
        sha: $sha
        merge: $merge
        ready: $f.ready
        done: $f.done
        cleanup_error: (
            if $rm.exit_code != 0 {
                $rm.stderr | str trim
            }
        )
        next: (
            if $f.done { $"spec.nu frontier ($spec) for the review step" } else if ($f.ready | is-empty) { "wait for the running workers" } else { $"start workers for ($f.ready | str join ', ') \(spec.nu frontier ($spec) has the commands\)" }
        )
    }
}

def worktree-path [repo: string, branch: string]: nothing -> oneof<string, nothing> {
    git-out $repo [worktree list --porcelain]
    | split row "\n\n"
    | where ($it | str contains $"branch refs/heads/($branch)\n") or ($it | str ends-with $"branch refs/heads/($branch)")
    | get -o 0
    | if $in == null { null } else {
        lines | first | str replace "worktree " ""
    }
}

# Sends `text` and waits only for its receipt.
def ask [agent: string, text: string] {
    ^herdr agent prompt $agent $text --wait --until working --until blocked --timeout $prompt_timeout_ms | complete | ignore
}
