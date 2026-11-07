# The landing queue's decisions, kept free of side effects so that
# queue-test.nu can drive them through the cases a real batch produced.

# Send-backs for CI failures before the harness takes the PR over;
# references/landing.md sets the same limit for landing by hand.
export const max_fix_asks = 3
# Merges of the base asked of one PR. Each comes from another PR landing
# first, so a PR waits through several before it is a sign of trouble.
export const max_merge_asks = 5

# Decides one pass over the queue.
#
# `items` are the queued PRs in queue order, each:
#   pr: int
#   verdict: record   # land.nu --dry-run's record; `result` is what counts
#   stacked: bool     # its base is the branch of another open PR
#   worker: string?   # herdr agent of the PR's worktree, null when none
#   worker_state: string  # watch's states: working busy blocked stopped gone
#   asks: list<record>    # earlier asks to this worker: {kind, sha}
#
# Returns `{actions, stop}`. Each action is `{pr, action, reason}` with action
# one of: land, ask-merge, ask-fix, wait, skip, drop. `stop` is null, or the
# first item the rules cannot settle: `{pr, result, detail, next}`; actions
# after it are still listed, for a dry run to show. A queue where nothing can
# move and no worker is at work stops as `stalled`, rather than passing over
# the same PRs until the timeout.
#
# Only the head, the first PR that can move, is asked to merge the base or
# landed through an update of the base: every landing moves the base again, so
# bringing every PR up to date at once spends a CI run on each and lands one.
# Any other PR lands only when it needs no update (`would-merge`).
#
# @example
# decide [{pr: 1, verdict: {result: would-merge, sha: a}, stacked: false, worker: kn-1, worker_state: stopped, asks: []}]
# # => {actions: [{pr: 1, action: land, reason: "..."}], stop: null}
export def decide [items: list<record>]: nothing -> record {
    mut head_taken = false
    mut actions = []
    mut stop: any = null
    for it in $items {
        let d = decide-one $it $head_taken
        if $d.head { $head_taken = true }
        $actions = $actions | append {pr: $it.pr, action: $d.action, reason: $d.reason}
        if $d.stop != null and $stop == null {
            $stop = $d.stop | insert pr $it.pr | insert agent $it.worker | insert sha ($it.verdict.sha? | default null)
        }
    }
    let moving = $actions | any {|a| $a.action in [land ask-merge ask-fix wait] }
    let at_work = $items | any {|i| $i.worker_state in [working busy] }
    if $stop == null and not $moving and not $at_work and ($items | is-not-empty) {
        let why = $actions | where action == skip | each {|a| $"#($a.pr): ($a.reason)" } | str join "; "
        $stop = {
            result: stalled
            pr: null
            agent: null
            sha: null
            detail: $"no queued PR can move: ($why)"
            next: "queue the PR a stacked one sits on, retarget it (`gh pr edit <pr> --base <default>`), get a draft marked ready, or `queue.nu remove` it"
        }
    }
    {actions: $actions, stop: $stop}
}

# One PR's decision. `head` says whether this PR took the head position.
def decide-one [it: record, head_taken: bool]: nothing -> record {
    let v = $it.verdict
    let sha = $v.sha? | default null
    let r = {|action: string, reason: string| {
        action: $action
        reason: $reason
        head: false
        stop: null
    } }
    let halt = {|result: string, detail: string, next: string| {
        action: stop
        reason: $detail
        head: false
        stop: {result: $result, detail: $detail, next: $next}
    } }

    # The PR's own state comes first: a merged PR's worker no longer matters
    match $v.result {
        merged => { return (do $r drop "merged") }
        closed | fork | manual-land | error | merge-refused => {
            return (do $halt $v.result $v.detail $v.next)
        }
    }
    if $it.worker_state == blocked {
        return (
            (do
                $halt
                blocked
                $"($it.worker) waits on a permission prompt or a dialog"
                "answer it per triage.md, then run queue.nu again"
            )
        )
    }
    if $it.stacked {
        return (do $r skip "stacked on a PR that has not landed")
    }
    if $it.worker_state in [working busy] {
        # A worker carrying out the merge it was asked for keeps the head, or
        # the next conflicting PR would be asked for a merge as well
        let merging = ($it.asks | last | get -o kind) == "merge"
        return {
            action: skip
            reason: $"worker is ($it.worker_state)"
            head: ($merging and not $head_taken)
            stop: null
        }
    }
    if $v.result == draft {
        return (do $r skip "draft")
    }

    let asked = {|kind: string|
        $it.asks | where kind == $kind
    }
    let asked_here = {|kind: string|
        do $asked $kind | any {|a| $a.sha == $sha }
    }
    # The worker stopped after an ask without moving the head: it has a
    # question, or judged the failure not to be this PR's
    let no_progress = {|kind: string| (do
        $halt
        no-progress
        $"($it.worker) stopped after the ($kind) ask without pushing"
        $"read its last turn with `herdr agent read ($it.worker) --lines 40`; answer it, or settle the failure per triage.md"
    ) }
    let no_worker = {|need: string| (do
        $halt
        no-worker
        $"the PR needs ($need), but no worker runs in its worktree"
        "start a worker on the branch with spawn.nu, or bring it to the user"
    ) }

    match $v.result {
        ci-failed => {
            if (do $asked_here fix) { return (do $no_progress fix) }
            if (do $asked fix | length) >= $max_fix_asks {
                return (
                    (do
                        $halt
                        send-back-limit
                        $"CI failed after ($max_fix_asks) send-backs"
                        "bring the issue to the user"
                    )
                )
            }
            if $it.worker == null { return (do $no_worker "a CI fix") }
            # A fix does not take the head: the next PR lands meanwhile
            do $r ask-fix "CI failed"
        }
        optional-failed => {
            do $halt optional-failed $v.detail $v.next
        }
        would-merge => {
            {
                action: land
                reason: "lands without an update"
                head: (not $head_taken)
                stop: null
            }
        }
        _ if $head_taken => {
            do $r skip $"($v.result); waits to be the head"
        }
        conflict => {
            if (do $asked_here merge) { return (do $no_progress merge) }
            if (do $asked merge | length) >= $max_merge_asks {
                return (
                    (do
                        $halt
                        conflict-limit
                        $"conflicted with the base ($max_merge_asks) times"
                        "bring it to the user; another order of landing may avoid it"
                    )
                )
            }
            if $it.worker == null { return (do $no_worker "a merge of the base") }
            {
                action: ask-merge
                reason: "head conflicts with the base"
                head: true
                stop: null
            }
        }
        would-update => {
            {
                action: land
                reason: "head; land.nu merges the base and waits for CI"
                head: true
                stop: null
            }
        }
        pending | no-checks | unknown-mergeable | unknown | updated | head-moved => {
            {
                action: wait
                reason: $v.result
                head: true
                stop: null
            }
        }
        _ => {
            (do
                $halt
                $v.result
                ($v.detail? | default "")
                ($v.next? | default "bring it to the user")
            )
        }
    }
}
