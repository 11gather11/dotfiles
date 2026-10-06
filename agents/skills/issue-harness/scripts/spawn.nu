#!/usr/bin/env nu
# Starts one worker: a wt worktree, the herdr workspace its post-start hook
# opens, Claude Code in that workspace's first pane, and the first prompt.
# Prints one JSON line describing the worker, or why it could not start.

const worker_brief = path self ../references/worker-brief.md

# The caller runs this under a 600 s Bash timeout, and a killed script prints
# nothing at all, so every wait below is bounded and the bounds add up to
# about 7.5 minutes. That leaves room for `git pull`, `wt switch` and the
# capacity check, which have no timeout of their own.
#
# wt's post-start hook opens the workspace in the background; it normally
# appears within seconds.
const workspace_budget = 60sec
const workspace_poll = 2sec
# A new pane loads direnv and the Nix shell before its prompt is back, and
# herdr refuses to start an agent until then. This bounds the busy retries and
# herdr's readiness wait together.
const start_budget = 300sec
const busy_retry = 10sec
# herdr's own cap on one readiness wait is 300 s; one attempt may not take
# the whole stage, or a busy retry never gets its turn.
const readiness_timeout = 180sec
# Claude keeps starting after herdr's readiness wait gives up; on a loaded
# machine it comes up a little later, unnamed.
const adopt_window = 60sec
const adopt_poll = 5sec
# Waiting for the adopted Claude to take input, then for it to start working
# on the prompt.
const ready_budget = 45sec
const prompt_timeout = 30sec

# Machine-wide default when no `max-workers` file sets one.
const default_max_workers = 4
# Worker names are `<repo prefix>-<issue number>`, e.g. pg-264. The user's own
# sessions are unnamed or named otherwise, and are never counted.
const worker_name = '^[a-z][a-z0-9]*-[0-9]+$'
# kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical. A busy
# Mac sits at warn with a third of its memory free, so only critical refuses.
const memory_critical = 4

# Start a worker for one issue and send it its first prompt.
#
# The last line of stdout is always one JSON record: the worker on success,
# `{name, branch, stage, error}` on failure. Exits 1 on failure and 2 when
# refused for capacity, so the harness can wait and retry. Safe to rerun with
# the same arguments: an existing worktree, workspace or Claude is reused, and
# a worker already working is not prompted again.
def main [
    name: string # herdr agent name, unique among live agents, e.g. pg-264
    branch: string # worktree branch, e.g. issue-264-lint
    prompt: string # first prompt, usually one line naming the issue
    --force # start even when the capacity limits say to wait
    --base: string # branch to cut a new branch from, at its latest on origin; the default branch when omitted
]: nothing -> nothing {
    let outcome = try {
        spawn $name $branch $prompt $force $base
    } catch {|e| {
        exit: 1
        out: {
            name: $name
            branch: $branch
            stage: (stage-of $e)
            error: $e.msg
        }
    } }
    # A single line survives callers that keep only the tail of the output
    $outcome.out | to json --raw | print
    exit $outcome.exit
}

# Runs every step in order and returns `{exit, out}` for `main` to print.
def spawn [
    name: string
    branch: string
    prompt: string
    force: bool
    base: oneof<string, nothing>
]: nothing -> record {
    let ctx = step setup { context $name }

    let existing = step worktree { worktree-of $ctx.repo $branch }
    step name { check-name $name $existing }

    if not $force {
        let cap = step capacity { capacity $ctx $name }
        if $cap.error != null {
            return {
                exit: 2
                out: ({name: $name, branch: $branch, stage: capacity} | merge $cap)
            }
        }
    }

    step pull {
        external [
            git
            -C
            $ctx.repo
            pull
            --quiet
            --ff-only
        ] | ignore
    }
    let path = step worktree {
        $existing | default { create-worktree $ctx.repo $branch $base }
    }
    let ws = step workspace { workspace-for $path $branch ($existing != null) }
    let pane = step workspace {
        herdr-ok [pane list --workspace $ws] | get panes.0.pane_id
    }

    step start { start-agent $pane $name $ctx.brief }
    let status = step ready { wait-ready $name }
    # A rerun after an attempt whose prompt did land must not send it twice
    if $status != working {
        step prompt { send-prompt $name $prompt }
    }

    let agent = step prompt {
        herdr-ok [agent get $name] | get agent
    }
    let worker = {
        name: $name
        branch: $branch
        workspace: $ws
        pane: $pane
        worktree: $agent.cwd
        status: $agent.agent_status
    }
    {
        exit: 0
        # `base` only when given, so the default record is unchanged
        out: (
            if $base == null { $worker } else {
                $worker | insert base $base
            }
        )
    }
}

# Runs `f`, labelling any error it raises with `stage` for the failure record.
# An error that already carries a stage keeps it.
def step [stage: string, f: closure] {
    try {
        do $f
    } catch {|e|
        let code = if (stage-of $e) == internal { $"harness::($stage)" } else { $e.details.code }
        error make {msg: $e.msg, code: $code}
    }
}

# The stage `step` recorded on an error, or `internal` for one raised outside.
def stage-of [e: record]: nothing -> string {
    let code = $e.details?.code? | default ""
    if ($code | str starts-with "harness::") {
        $code | str replace "harness::" ""
    } else {
        "internal"
    }
}

# Runs an external command and returns its stdout, or fails with its trimmed
# stderr, which carries the real cause. The command line is a list so that its
# flags are not taken for this command's own.
def external [argv: list<string>]: nothing -> string {
    let r = ^($argv | first) ...($argv | skip 1) | complete
    if $r.exit_code != 0 {
        let why = $r.stderr | str trim | default -e $"exit status ($r.exit_code)"
        error make {msg: $"($argv | first 2 | str join ' ') failed: ($why)"}
    }
    $r.stdout
}

# Runs herdr and returns `{ok: true, result}` or `{ok: false, code, message}`.
# herdr reports errors as JSON on stderr; anything else there is kept as text.
def herdr-try [args: list<string>]: nothing -> record {
    let r = ^herdr ...$args | complete
    if $r.exit_code == 0 {
        {
            ok: true
            result: ($r.stdout | from json | get result)
        }
    } else {
        let parsed = try {
            $r.stderr | from json
        } catch { null }
        match $parsed {
            {error: {code: $code, message: $message}} => {ok: false, code: $code, message: $message}
            _ => {
                ok: false
                code: unknown
                message: ($r.stderr | str trim | default -e $"exit status ($r.exit_code)")
            }
        }
    }
}

# Runs herdr and returns its `result`, failing with herdr's own error.
def herdr-ok [args: list<string>]: nothing -> record {
    let r = herdr-try $args
    if not $r.ok { error make {msg: $"herdr ($args | first 2 | str join ' '): ($r.code): ($r.message)"} }
    $r.result
}

# Calls `f` every `delay` until it returns non-null, and returns that value,
# or null once another call would start after `deadline`.
def poll-until [deadline: datetime, delay: duration, f: closure] {
    loop {
        let r = do $f
        if $r != null { return $r }
        if (date now) + $delay > $deadline { return null }
        sleep $delay
    }
}

# Milliseconds for a herdr `--timeout`, which must be positive.
def ms [d: duration]: nothing -> string {
    [
        $d
        1sec
    ] | math max | $in / 1ms | into int | into string
}

# Resolves the main checkout and the per-repo state directory, and writes the
# brief this worker's Claude is started with.
def context [name: string]: nothing -> record {
    # The main checkout, even when called from a linked worktree
    let repo = external [git rev-parse --path-format=absolute --git-common-dir] | str trim | path dirname
    let root = $env.XDG_STATE_HOME? | default ($env.HOME | path join .local/state) | path join harness
    let state = $root | path join ($repo | path basename)
    mkdir $state

    # The machine-local brief rides after the shared one; it holds what the
    # repository cannot publish (local data paths, private hosts)
    let local_brief = $state | path join brief.md
    let brief = $state | path join $"($name).brief.md"
    [
        (open --raw $worker_brief)
        (if ($local_brief | path exists) { open --raw $local_brief } else { "" })
    ]
    | str join "\n\n"
    | save --force $brief

    {
        repo: $repo
        root: $root
        state: $state
        brief: $brief
    }
}

# The checkout path of `branch`'s worktree, or null when it has none.
def worktree-of [repo: string, branch: string]: nothing -> oneof<string, nothing> {
    external [
        git
        -C
        $repo
        worktree
        list
        --porcelain
    ]
    | split row "\n\n"
    | where $it != ""
    | each { lines | parse "{key} {value}" | transpose -r -d }
    | where branch? == $"refs/heads/($branch)"
    | get -o 0.worktree
}

# Fails when `name` is live but is not this branch's worker: herdr names are
# unique, so the start would fail anyway, after a worktree had been made.
def check-name [name: string, worktree: oneof<string, nothing>]: nothing -> nothing {
    let r = herdr-try [agent get $name]
    if not $r.ok { return }
    let cwd = $r.result.agent.cwd
    if $worktree == null or not ($cwd | str starts-with $worktree) {
        error make {msg: $"agent name ($name) is already in use in pane ($r.result.agent.pane_id) \(($cwd)\)"}
    }
}

# Counts running workers against the machine and repo limits and checks
# memory pressure. `error` is null when there is room for one more.
def capacity [ctx: record, name: string]: nothing -> record {
    # idle and done workers are waiting on review and use no CPU. The worker
    # being (re)started is not counted against itself.
    let workers = herdr-ok [agent list]
    | get agents
    | where ($it.name? | default "") =~ $worker_name and $it.name != $name
    | where agent_status in [working blocked]
    # wt puts worktrees beside the main checkout as `<repo>.<branch>`
    let in_repo = $workers | where cwd == $ctx.repo or ($it.cwd | str starts-with $"($ctx.repo).")

    let machine_limit = read-limit ($ctx.root | path join max-workers) $default_max_workers
    let repo_limit = read-limit ($ctx.state | path join max-workers) $machine_limit
    let pressure = memory-pressure

    let error = [
        (
            if ($workers | length) >= $machine_limit { $"($workers | length) workers running on this machine, limit ($machine_limit)" }
        )
        (
            if ($in_repo | length) >= $repo_limit { $"($in_repo | length) workers running in this repository, limit ($repo_limit)" }
        )
        (
            if $pressure != null and $pressure >= $memory_critical { $"memory pressure is ($pressure) \(2 warn, 4 critical\)" }
        )
    ]
    | compact
    | match $in {
        [] => null
        $reasons => ($reasons | str join "; ")
    }

    {
        error: $error
        running: {
            machine: ($workers | length)
            repo: ($in_repo | length)
        }
        limits: {machine: $machine_limit, repo: $repo_limit}
        memory_pressure: $pressure
    }
}

# The integer in `file`, or `fallback` when the file does not exist.
def read-limit [file: string, fallback: int]: nothing -> int {
    if not ($file | path exists) { return $fallback }
    try {
        open --raw $file | str trim | into int
    } catch {
        error make {msg: $"($file) must hold a whole number"}
    }
}

# macOS's memory pressure level, or null where the kernel does not report it.
def memory-pressure []: nothing -> oneof<int, nothing> {
    if (which sysctl | is-empty) { return null }
    let r = ^sysctl -n kern.memorystatus_vm_pressure_level | complete
    if $r.exit_code != 0 { return null }
    try {
        $r.stdout | str trim | into int
    } catch { null }
}

# Makes the worktree for `branch` and returns its path. The branch can
# outlive its worktree, and `--create` refuses an existing branch.
# `base` applies only to a new branch, so a rerun reuses what the first run cut.
def create-worktree [repo: string, branch: string, base: oneof<string, nothing>]: nothing -> string {
    let has_branch = (^git -C $repo show-ref --verify --quiet $"refs/heads/($branch)" | complete).exit_code == 0
    if $has_branch {
        external [
            wt
            -C
            $repo
            switch
            $branch
            --no-cd
        ] | ignore
    } else if $base == null {
        external [
            wt
            -C
            $repo
            switch
            --create
            $branch
            --no-cd
        ] | ignore
    } else {
        # Cut from origin's copy rather than the local branch: fetching into a
        # local branch fails while the main checkout has it checked out, and a
        # remote-tracking base leaves the new branch without an upstream
        external [
            git
            -C
            $repo
            fetch
            --quiet
            origin
            $base
        ] | ignore
        external [
            wt
            -C
            $repo
            switch
            --create
            $branch
            --base
            $"origin/($base)"
            --no-cd
        ] | ignore
    }
    worktree-of $repo $branch
    | default { error make {msg: $"wt switch succeeded but git lists no worktree for ($branch)"} }
}

# The id of the herdr workspace for the worktree at `path`, waiting for wt's
# post-start hook to open it. That hook runs only when wt creates the
# worktree, so for one that already existed it is run again by hand.
def workspace-for [path: string, branch: string, existed: bool]: nothing -> string {
    let find = {||
        herdr-ok [workspace list]
        | get workspaces
        | where ($it.worktree?.checkout_path? == $path) or $it.label == $branch
        | get -o 0.workspace_id
    }
    if $existed and (do $find) == null {
        external [
            wt
            -C
            $path
            hook
            post-start
            herdr
            --foreground
        ] | ignore
    }
    poll-until ((date now) + $workspace_budget) $workspace_poll $find
    | default {
        error make {
            msg: $"no herdr workspace for ($path) after ($workspace_budget); wt's post-start hook opens it only when run inside herdr \(HERDR_ENV set\)"
        }
    }
}

# Starts Claude as `name` in `pane`, or adopts one already running there.
def start-agent [pane: string, name: string, brief: string]: nothing -> nothing {
    let deadline = (date now) + $start_budget
    let started = poll-until $deadline $busy_retry {
        # A rerun finds the Claude an earlier attempt left in the pane
        if (adopt $pane $name) { return true }
        let wait = [
            ($deadline - (date now))
            $readiness_timeout
        ] | math min
        let r = herdr-try [
            agent
            start
            $name
            --kind
            claude
            --pane
            $pane
            --timeout
            (ms $wait)
            --
            --append-system-prompt-file
            $brief
        ]
        if $r.ok { return true }
        if $r.code == agent_pane_busy { return null }

        let until = [
            $deadline
            ((date now) + $adopt_window)
        ] | math min
        poll-until $until $adopt_poll {
            if (adopt $pane $name) { true }
        }
        | default { error make {msg: $"herdr agent start: ($r.code): ($r.message)"} }
    }
    if $started == null {
        error make {msg: $"pane ($pane) was still busy after ($start_budget); its shell never returned to a prompt"}
    }
}

# Reports whether `name` is running in `pane`, naming the pane's Claude when it
# came up unnamed. herdr stops waiting for readiness at its timeout, but Claude
# keeps starting; on a loaded machine it comes up after herdr has given up.
# Fails when the name or the pane's Claude belongs to someone else.
def adopt [pane: string, name: string]: nothing -> bool {
    let by_name = herdr-try [agent get $name]
    if $by_name.ok {
        let at = $by_name.result.agent.pane_id
        if $at == $pane { return true }
        error make {msg: $"agent name ($name) is live in pane ($at), not in this worker's pane ($pane)"}
    }

    let here = herdr-try [agent get $pane]
    if not $here.ok or $here.result.agent.agent? != claude { return false }
    match $here.result.agent.name? {
        null => {
            herdr-ok [agent rename $pane $name] | ignore
            true
        }
        $other => {
            error make {msg: $"pane ($pane) already runs a Claude named ($other)"}
        }
    }
}

# Waits until `name` can take a prompt and returns its status. A worker that
# is already `working` is returned as is: an earlier attempt prompted it.
def wait-ready [name: string]: nothing -> string {
    let status = herdr-ok [agent get $name] | get agent.agent_status
    if $status in [working idle done] { return $status }
    let r = herdr-try [
        agent
        wait
        $name
        --until
        idle
        --until
        done
        --timeout
        (ms $ready_budget)
    ]
    if not $r.ok {
        let now = herdr-ok [agent get $name] | get agent.agent_status
        error make {msg: $"($name) was not ready for input after ($ready_budget) \(status ($now)\): ($r.code): ($r.message)"}
    }
    herdr-ok [agent get $name] | get agent.agent_status
}

# Sends the first prompt and confirms it landed. herdr's wait only confirms
# receipt, and it can time out or stall although the prompt arrived, so the
# agent's state decides; the prompt is never sent a second time.
def send-prompt [name: string, prompt: string]: nothing -> nothing {
    let r = herdr-try [
        agent
        prompt
        $name
        $prompt
        --wait
        --until
        working
        --until
        blocked
        --timeout
        (ms $prompt_timeout)
    ]
    if $r.ok { return }
    # blocked after a prompt sent to an idle agent means it is asking for a
    # permission on the prompt's first step
    let status = herdr-ok [agent get $name] | get agent.agent_status
    if $status not-in [working blocked] {
        error make {msg: $"prompt not confirmed \(status ($status)\): ($r.code): ($r.message)"}
    }
}
