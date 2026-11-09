# Which tickets of a spec can start, kept free of side effects so that
# spec-test.nu can drive it. spec.nu and integrate.nu read GitHub and git and
# hand the facts in.

# Splits a spec's tickets by what they wait on.
#
# `tickets`: `{number, title, state, blocked_by: [{number, state}]}`.
# `integrated`: ticket numbers already merged into the integration branch.
# `running`: ticket numbers that have a branch already, so a worker has them.
#
# A ticket is ready when it is open, not integrated, not running, and every
# blocker is closed, or is a ticket of this spec already integrated (its issue
# closes only when the spec lands on the base). Done means every open ticket
# is in.
#
# @example
# frontier [{number: 2, title: b, state: OPEN, blocked_by: [{number: 1, state: OPEN}]}] [1] []
# # => {ready: [2], waiting: [], running: [], done: false, stuck: false}
export def frontier [tickets: list<record>, integrated: list<int>, running: list<int>]: nothing -> record {
    let ours = $tickets | get number
    let open = $tickets | where state == "OPEN" and number not-in $integrated
    let judged = $open | where number not-in $running | each {|t|
        let waits = $t.blocked_by | where {|b|
            $b.state != "CLOSED" and not ($b.number in $ours and $b.number in $integrated)
        }
        {number: $t.number, title: $t.title, on: ($waits | get number)}
    }
    let ready = $judged | where ($it.on | is-empty)
    let waiting = $judged | where ($it.on | is-not-empty)
    let in_flight = $open | where number in $running | get number
    {
        ready: ($ready | get number)
        waiting: ($waiting | select number on)
        running: $in_flight
        done: ($open | is-empty)
        # Tickets remain, yet nothing can start and nothing is under way: a
        # cycle, or a blocker outside the spec that stays open
        stuck: (
            ($open | is-not-empty) and ($ready | is-empty) and ($in_flight | is-empty)
        )
    }
}
