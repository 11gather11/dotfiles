#!/usr/bin/env nu
# Waits on several workers at once and returns as soon as one of them needs
# the harness. Unlike `herdr agent wait`, a worker whose turn ended while a
# background shell or monitor still runs counts as working.

use harness.nu [worker-state]

# Wait until one of `agents` stops, blocks or disappears.
#
# Prints one JSON line: `{result, agent, agent_status, footer}`, where result
# is `stopped`, `blocked`, `gone` or `timeout`. A worker already stopped when
# this starts is returned at once, so pass only the workers you are waiting on.
# Exit status: 0 a worker needs the harness; 2 timeout; 1 error.
#
# @example
# watch.nu kn-1109 kn-1112 kn-1124
def main [
    ...agents: string           # herdr agent names
    --interval: duration = 30sec # time between two reads of every pane
    --timeout: duration = 2hr    # give up and report `timeout`
] {
    if ($agents | is-empty) {
        {result: error, detail: "usage: watch.nu <agent>... [--interval 30sec] [--timeout 2hr]"} | to json --raw | print
        exit 1
    }
    let deadline = (date now) + $timeout
    loop {
        let hit = $agents
        | each {|a| worker-state $a | insert agent $a }
        | where state not-in [working busy]
        | get -o 0
        if $hit != null {
            {
                result: $hit.state
                agent: $hit.agent
                agent_status: $hit.agent_status
                footer: $hit.footer
            } | to json --raw | print
            exit 0
        }
        if (date now) + $interval > $deadline {
            {
                result: timeout
                agents: $agents
                detail: $"none stopped within ($timeout)"
            } | to json --raw | print
            exit 2
        }
        sleep $interval
    }
}
