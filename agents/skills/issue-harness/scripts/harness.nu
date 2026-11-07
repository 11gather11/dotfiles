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
