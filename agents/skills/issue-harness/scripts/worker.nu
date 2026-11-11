#!/usr/bin/env nu
# What the harness does to one worker by hand: read it, prompt it, press a
# key in it. The same commands work whether the workers run in the herdr TUI
# or in herdr-core (herdr-app's terminals): each goes to the multiplexer this
# harness runs in.

use harness.nu [agent-get read-worker prompt-worker press-keys current-mux]

def main [] {
    {result: error, detail: "usage: worker.nu get|read|prompt|keys <name> …"} | to json --raw | print
    exit 1
}

# The worker's status, folder and pane or terminal, as one JSON line.
#
# @example
# worker.nu get pg-264
def "main get" [name: string] {
    let a = agent-get $name (current-mux)
    if $a == null {
        {name: $name, state: gone} | to json --raw | print
        exit 1
    }
    {
        name: $name
        mux: (current-mux)
    } | merge $a | to json --raw | print
}

# The last lines of the worker's screen and history.
#
# @example
# worker.nu read pg-264 --lines 40
def "main read" [name: string, --lines: int = 40] {
    read-worker $name --lines $lines | print
}

# Sends `text` and waits only for its receipt: the worker working, or blocked
# on a permission. Prints the status it ended on; exits 1 when the receipt was
# not seen, which does not prove the prompt was lost: read it before sending
# again.
#
# @example
# worker.nu prompt pg-264 "Merge origin/main and push."
def "main prompt" [name: string, text: string, --timeout: duration = 30sec] {
    let status = prompt-worker $name $text --timeout $timeout
    {name: $name, status: $status} | to json --raw | print
    if $status == null { exit 1 }
}

# Presses keys in the worker: a menu option's number, esc, enter.
#
# @example
# worker.nu keys pg-264 2
# worker.nu keys pg-264 esc
def "main keys" [name: string, ...keys: string] {
    press-keys $name $keys
}
