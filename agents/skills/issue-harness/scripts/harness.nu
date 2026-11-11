# What land.nu, queue.nu and watch.nu share: where the harness keeps its
# machine-local settings, and how a worker's pane is read.

# Footer text Claude Code shows while a background shell or monitor of the
# turn is still running ("⏵⏵ auto mode on · 1 shell, 1 monitor"). herdr
# reports such a worker as idle or done, but its work is not finished. Only
# the footer below the prompt box is searched: the transcript above it quotes
# CI and shell output ("render is still running").
const background_footer = '(?i)\b\d+\s+(shells?|monitors?|background tasks?)\b|still running'

# The harness's state directory for `repo`: `~/.local/state/harness/<name>`.
#
# @example
# state-dir /Users/me/ghq/github.com/me/app   # => ~/.local/state/harness/app
export def state-dir [repo: string]: nothing -> string {
    $env.XDG_STATE_HOME?
    | default ($env.HOME | path join .local/state)
    | path join harness ($repo | path basename)
}

# Whether the empty marker file `name` is present in `repo`'s state directory.
export def setting-on [repo: string, name: string]: nothing -> bool {
    state-dir $repo | path join $name | path exists
}

# The main checkout, even when called from a linked worktree.
export def main-checkout []: nothing -> string {
    ^git rev-parse --path-format=absolute --git-common-dir | str trim | path dirname
}

# Where the workers run: `hc` (herdr-core, the terminals herdr-app shows) when
# the harness itself runs in one of its terminals, else `herdr`, the TUI. A
# harness started in either finds and drives its workers in the same one, so
# the two never see each other's.
export def current-mux []: nothing -> string {
    if ($env.HC_TERMINAL_ID? | is-not-empty) { "hc" } else { "herdr" }
}

# The named agents running in `mux`, as `{name, cwd, status}`. Workers are
# named when they start; an unnamed terminal is not one. Empty when `mux` is
# not running.
export def agents-in [mux: string]: nothing -> list<record> {
    match $mux {
        hc => {
            let r = ^hc ls --json | complete
            if $r.exit_code != 0 { return [] }
            $r.stdout
            | from json
            | get terminals
            | where ($it.name? | is-not-empty)
            # `hc ls` carries no status; each worker's comes from `hc get`
            | each {|t| {name: $t.name, cwd: $t.cwd, status: (agent-get $t.name hc).status?} }
        }
        herdr => {
            let r = ^herdr agent list | complete
            if $r.exit_code != 0 { return [] }
            $r.stdout
            | from json
            | get result.agents
            | where ($it.name? | is-not-empty)
            | each {|a| {name: $a.name, cwd: $a.cwd, status: $a.agent_status} }
        }
        _ => (error make {msg: $"unknown multiplexer: ($mux)"})
    }
}

# The agent whose directory is the worktree of `branch`, or null when no
# worktree or no agent holds it.
export def worker-of [repo: string, branch: string]: nothing -> oneof<string, nothing> {
    let path = ^git -C $repo worktree list --porcelain
    | split row "\n\n"
    | where $it != ""
    | each { lines | parse "{key} {value}" | transpose -r -d }
    | where branch? == $"refs/heads/($branch)"
    | get -o 0.worktree
    if $path == null { return null }
    agents-in (current-mux)
    | where $it.cwd == $path or ($it.cwd | str starts-with $"($path)/")
    | get -o 0.name
}

# Classifies a worker for the harness:
# - `working`: the multiplexer says so.
# - `busy`: idle or done, but a background shell or monitor is still running.
# - `blocked`: a permission prompt or a dialog waits for an answer.
# - `stopped`: the turn is over; read the screen for a PR URL or a question.
# - `gone`: no such agent, as after land.nu removed its worktree.
# `footer` carries the lines the decision was read from.
export def worker-state [
    name: string
    --mux: string  # where the worker runs; default: current-mux
]: nothing -> record {
    let mux = $mux | default (current-mux)
    let agent = agent-get $name $mux
    if $agent == null {
        return {
            state: gone
            agent_status: null
            footer: []
        }
    }
    let status = $agent.status
    match $status {
        working => {
            return {
                state: working
                agent_status: $status
                footer: []
            }
        }
        blocked => {
            return {
                state: blocked
                agent_status: $status
                footer: []
            }
        }
    }
    let footer = footer-of $name $mux
    let state = if ($footer | any {|l| $l =~ $background_footer }) { "busy" } else { "stopped" }
    {state: $state, agent_status: $status, footer: $footer}
}

# The lines below the last prompt line (`❯`) of the visible screen: the
# status bar where Claude Code lists background shells and monitors.
def footer-of [name: string, mux: string]: nothing -> list<string> {
    # `hc read` prints the screen alone unless asked for history.
    let r = match $mux {
        hc => (^hc read $name | complete)
        _ => (^herdr agent read $name --source visible | complete)
    }
    if $r.exit_code != 0 { return [] }
    let screen = $r.stdout | lines
    let prompt = $screen | enumerate | where ($it.item | str trim | str starts-with "❯") | last
    let footer = if $prompt == null {
        $screen | last 4
    } else {
        $screen | skip ($prompt.index + 1)
    }
    $footer | str trim | where $it != "" and not ($it | str starts-with "─")
}

# ── talking to a worker ──
# What the harness does to a worker, once for both multiplexers: the scripts
# call these, and worker.nu hands them to the harness itself.

# `{status, cwd, where}` of the agent `name` in `mux`, or null when it is not
# running. `where` is herdr's pane or hc's terminal address. hc's status is the
# program's own OSC 7501 report, null until it sends one; herdr's is its
# reading of the agent.
export def agent-get [name: string, mux: string]: nothing -> oneof<record, nothing> {
    match $mux {
        hc => {
            let r = ^hc get $name --json | complete
            if $r.exit_code != 0 { return null }
            let t = $r.stdout | from json
            if $t.state != "live" { return null }
            {
                status: ($t.status?.state?)
                cwd: $t.cwd
                where: $t.address
            }
        }
        _ => {
            let r = ^herdr agent get $name | complete
            if $r.exit_code != 0 { return null }
            let a = $r.stdout | from json | get result.agent
            {status: $a.agent_status, cwd: $a.cwd, where: $a.pane_id}
        }
    }
}

# The last `lines` lines of the worker's screen and history, soft-wrapped
# lines joined where the multiplexer can. Empty when it cannot be read.
export def read-worker [
    name: string
    --lines: int = 40
    --mux: string  # default: current-mux
]: nothing -> string {
    let mux = $mux | default (current-mux)
    let r = match $mux {
        hc => (^hc read $name --lines $lines | complete)
        _ => (
            ^herdr agent read $name --source recent-unwrapped --lines $lines
            | complete
        )
    }
    if $r.exit_code == 0 { $r.stdout } else { "" }
}

# Types `text` into the worker and presses enter, then waits only for its
# receipt: the worker `working`, or `blocked` on a permission its first step
# needs. Returns the status it ended on; null when it was gone or the wait ran
# out, which does not prove the prompt was lost.
export def prompt-worker [
    name: string
    text: string
    --timeout: duration = 30sec
    --mux: string  # default: current-mux
]: nothing -> oneof<string, nothing> {
    let mux = $mux | default (current-mux)
    match $mux {
        hc => {
            # hc send refuses a blocked terminal, as a prompt should not answer
            # a permission it never read
            if (^hc send $name $text | complete).exit_code != 0 { return null }
            let deadline = (date now) + $timeout
            loop {
                let status = (agent-get $name hc).status?
                if $status in [working blocked] { return $status }
                if (date now) + 1sec > $deadline { return null }
                sleep 1sec
            }
        }
        _ => {
            let ms = $timeout / 1ms | into int | into string
            ^herdr agent prompt $name $text --wait --until working --until blocked --timeout $ms | complete | ignore
            (agent-get $name herdr).status?
        }
    }
}

# Presses keys in the worker: a menu option's number, `esc`, `enter`.
export def press-keys [
    name: string
    keys: list<string>
    --mux: string  # default: current-mux
]: nothing -> nothing {
    let mux = $mux | default (current-mux)
    let r = match $mux {
        hc => (^hc keys $name ...$keys | complete)
        _ => (^herdr agent send-keys $name ...$keys | complete)
    }
    if $r.exit_code != 0 { error make {msg: $"keys to ($name): ($r.stderr | str trim)"} }
}

# The check names the base branch requires, from its rulesets and its classic
# protection together; empty when neither can be read or neither requires any.
# `gh pr checks --required` cannot stand in: it lists only required checks
# that already exist on the head, and a job that `needs` others is created
# late, so it would report "none required" exactly while one is outstanding.
export def required-checks [base: string]: nothing -> list<string> {
    let rules = ^gh api $"repos/{owner}/{repo}/rules/branches/($base)" | complete
    let from_rules = if $rules.exit_code == 0 {
        $rules.stdout
        | from json
        | where type == "required_status_checks"
        | get -o parameters.required_status_checks
        | flatten
        | get -o context
        | default []
    } else { [] }
    let branch = ^gh api $"repos/{owner}/{repo}/branches/($base)" | complete
    let from_protection = if $branch.exit_code == 0 {
        $branch.stdout | from json | get -o protection.required_status_checks.contexts | default []
    } else { [] }
    $from_rules | append $from_protection | uniq
}

# Runs the repository's integration check, the command in
# `~/.local/state/harness/<repo>/check`, in `dir` under the machine-wide heavy
# lock that workers' whole-machine checks also take, so two never load the
# machine at once. Output goes to `logs/<label>.log` in the state directory.
#
# Returns `{ok, detail, log}`; a lock wait that ran out is not ok either, and
# says so.
export def heavy-check [repo: string, dir: string, label: string]: nothing -> record {
    let cmd_file = state-dir $repo | path join check
    if not ($cmd_file | path exists) {
        error make {msg: $"no integration check: write the command to run before a merge into ($cmd_file), e.g. `just check`"}
    }
    let cmd = open --raw $cmd_file | str trim
    let logs = state-dir $repo | path join logs
    mkdir $logs
    let log = $logs | path join $"($label).log"
    let lock = state-dir $repo | path dirname | path join heavy.lock
    let locker = if (which lockf | is-not-empty) { [lockf -k -t 300 $lock] } else { [flock -w 300 $lock] }
    let r = do {
        cd $dir
        ^($locker | first) ...($locker | skip 1) sh -c $cmd
    } | complete
    $"$ ($cmd)\n($r.stdout)\n($r.stderr)" | save --force $log
    match $r.exit_code {
        0 => {
            ok: true
            detail: $"($cmd) passed"
            log: $log
        }
        75 => {ok: false, detail: "the heavy lock stayed taken for 5 minutes; run it again", log: $log}
        $c => {
            ok: false
            detail: $"($cmd) failed \(exit ($c)\): ($r.stdout | lines | last 15 | str join '\n')"
            log: $log
        }
    }
}
