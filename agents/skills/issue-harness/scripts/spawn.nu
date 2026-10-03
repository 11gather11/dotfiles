#!/usr/bin/env nu
# Starts one worker: a wt worktree, the herdr workspace its post-start hook
# opens, Claude Code in that workspace's first pane, and the first prompt.
# Prints one JSON record describing the worker.

const worker_brief = path self ../references/worker-brief.md

# Retries `f` every `delay` until it returns non-null, or errors after `tries`.
def retry [
    tries: int
    delay: duration
    what: string
    f: closure
] {
    for _ in 1..$tries {
        let r = do $f
        if $r != null { return $r }
        sleep $delay
    }
    error make {msg: $"gave up waiting for ($what)"}
}

# Start a worker for one issue and send it its first prompt.
def main [
  name: string     # herdr agent name, unique among live agents, e.g. pg-264
  branch: string   # worktree branch, e.g. issue-264-lint
  prompt: string   # first prompt, usually one line naming the issue
] {
    # The main checkout, even when called from a linked worktree
    let repo = git rev-parse --path-format=absolute --git-common-dir | path dirname
    let repo_name = $repo | path basename
    let state = $env.XDG_STATE_HOME? | default ($env.HOME | path join .local/state) | path join harness $repo_name
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

    git -C $repo pull --quiet --ff-only
    cd $repo
    wt switch --create $branch --no-cd | complete | ignore

    # wt's post-start hook opens the workspace asynchronously
    let ws = retry 20 2sec "the herdr workspace" {
        herdr workspace list
        | from json
        | get result.workspaces
        | where label == $branch
        | get -o 0.workspace_id
    }
    let pane = herdr pane list --workspace $ws | from json | get result.panes.0.pane_id

    # A new pane is busy loading direnv and the Nix shell, and refuses the agent
    # until its prompt is back
    retry 18 10sec "the pane to accept the agent" {
        let r = herdr agent start $name --kind claude --pane $pane --timeout 60000 -- --append-system-prompt-file $brief | complete
        if $r.exit_code == 0 { true } else {
            # herdr writes its error envelope to stderr
            let code = $r.stderr | from json | get -o error.code
            if $code != "agent_pane_busy" { error make {msg: $"agent start failed: ($r.stderr)"} }
        }
    }

    herdr agent prompt $name $prompt --wait --timeout 30000 | complete | ignore
    let status = herdr agent get $name | from json | get result.agent.agent_status
    {
        name: $name
        branch: $branch
        workspace: $ws
        pane: $pane
        status: $status
    } | to json --raw
}
