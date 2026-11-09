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

# The herdr agent whose directory is the worktree of `branch`, or null when no
# worktree or no agent holds it.
export def worker-of [repo: string, branch: string]: nothing -> oneof<string, nothing> {
    let path = ^git -C $repo worktree list --porcelain
    | split row "\n\n"
    | where $it != ""
    | each { lines | parse "{key} {value}" | transpose -r -d }
    | where branch? == $"refs/heads/($branch)"
    | get -o 0.worktree
    if $path == null { return null }
    let r = ^herdr agent list | complete
    if $r.exit_code != 0 { return null }
    $r.stdout
    | from json
    | get result.agents
    | where $it.name? != null and ($it.cwd == $path or ($it.cwd | str starts-with $"($path)/"))
    | get -o 0.name
}

# Classifies a worker for the harness:
# - `working`: herdr says so.
# - `busy`: idle or done, but a background shell or monitor is still running.
# - `blocked`: a permission prompt or a dialog waits for an answer.
# - `stopped`: the turn is over; read the screen for a PR URL or a question.
# - `gone`: no such agent, as after land.nu removed its worktree.
# `footer` carries the lines the decision was read from.
export def worker-state [name: string]: nothing -> record {
    let r = ^herdr agent get $name | complete
    if $r.exit_code != 0 {
        return {
            state: gone
            agent_status: null
            footer: []
        }
    }
    let status = $r.stdout | from json | get result.agent.agent_status
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
    let footer = footer-of $name
    let state = if ($footer | any {|l| $l =~ $background_footer }) { "busy" } else { "stopped" }
    {state: $state, agent_status: $status, footer: $footer}
}

# The lines below the last prompt line (`❯`) of the visible screen: the
# status bar where Claude Code lists background shells and monitors.
def footer-of [name: string]: nothing -> list<string> {
    let r = ^herdr agent read $name --source visible | complete
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
