#!/usr/bin/env nu
# Checks what the harness takes for granted in a repository, which settings
# fit it, and which migrations (references/migrations.md) it has not done yet.
# Changes nothing but its own record of migrations: the settings are markers
# the user places, and the repository's rules are theirs.

use harness.nu [state-dir setting-on main-checkout required-checks current-mux]

const migrations_file = path self ../references/migrations.md

# Check the repository of the current directory.
#
# Prints one JSON line last: `{result, repo, checks, settings, migrations}`.
# `result` is `ok` or `needs-attention`; each check is `{name, ok, detail}`,
# or `{name, ok, next}` when it fails; `settings` lists the markers in
# `~/.local/state/harness/<repo>/` that fit; `migrations` the steps this
# repository has not caught up on, each `{id, title, steps}`.
# Exit status: 0 ok; 2 something needs attention; 1 error.
#
# @example
# setup.nu
def main [] {
    let out = try { check-all } catch {|e| {result: error, detail: $e.msg, next: "fix the cause, then run setup.nu again"} }
    $out | to json --raw | print
    exit (match $out.result {
        ok => 0
        error => 1
        _ => 2
    })
}

# Record migration `id` as done in this repository.
#
# @example
# setup.nu migrated 2026-11-09-drop-draft-prs
def "main migrated" [id: string] {
    let repo = main-checkout
    if $id not-in (all-migrations | get id) {
        {
            result: error
            detail: $"no migration ($id) in references/migrations.md"
        } | to json --raw | print
        exit 1
    }
    let done = done-migrations $repo | append $id | uniq
    save-done $repo $done
    {
        result: ok
        migrated: $id
        pending: (all-migrations | where id not-in $done | get id)
    } | to json --raw | print
}

def check-all []: nothing -> record {
    let repo = main-checkout
    cd $repo
    let pending = pending-migrations $repo
    let gh = ^gh repo view --json nameWithOwner,defaultBranchRef,squashMergeAllowed | complete
    if $gh.exit_code != 0 {
        error make {msg: $"gh repo view: ($gh.stderr | str trim); log in with `gh auth login` and run it from a GitHub checkout"}
    }
    let info = $gh.stdout | from json
    let base = $info.defaultBranchRef.name
    let approvals = required-approvals $base
    let no_land = setting-on $repo no-land

    let checks = [
        (
            (check
                "multiplexer"
                ($env.HERDR_ENV? == "1" or ($env.HC_TERMINAL_ID? | is-not-empty))
                $"this session runs inside ((current-mux)); workers start there"
                "start the harness from a herdr pane or a herdr-app terminal; workers are started and read through it"
            )
        )
        (
            check "required checks" (required-checks $base | is-not-empty)
            $"($base) requires: (required-checks $base | str join ', ')"
            $"require the CI's final job on ($base) in a ruleset: without one, land.nu reads a head whose checks are still being created as passed"
        )
        (
            check "squash merge" $info.squashMergeAllowed
            "squash merges are allowed"
            "allow squash merging in the repository settings; land.nu lands with `gh pr merge --squash`"
        )
        (
            check "approvals" ($approvals == 0 or $no_land)
            (if $approvals == 0 { "no approval is required to merge" } else { $"($approvals) approval\(s\) required, and no-land is set" })
            $"($base) requires ($approvals) approval\(s\), which nobody gives when one account opens and merges: set no-land, or require none"
        )
        (
            check "signing" (signs-for-agents $repo)
            "commits here sign with the key that needs no approval"
            $"ask the user whether agents may sign for this repository; if so, add an includeIf for ($repo)/ to ~/.gitconfig.ai-signing"
        )
        (
            check "CLAUDE.md" ([CLAUDE.md AGENTS.md] | any {|f| $repo | path join $f | path exists })
            "the repository has its own instructions"
            "write the repository's CLAUDE.md: the checks to pass before a PR and the PR format; the worker brief defers to it"
        )
    ]

    let state = state-dir $repo
    let settings = [
        (if $approvals > 0 and not $no_land {
            {marker: no-land, why: "merging needs an approval the harness cannot give", place: $"touch ($state)/no-land"}
        })
        (if not ($state | path join check | path exists) {
            {marker: check, why: "a spec's tickets merge into its integration branch only after this command passes (references/spec.md); write what can run on this machine", place: $"echo 'just check' > ($state)/check"}
        })
        (if not ($repo | path join docs agents issue-tracker.md | path exists) {
            {marker: null, why: "/to-tickets and the review read the repository's tracker setup", place: "run /mattpocock-skills:setup-matt-pocock-skills before working a spec"}
        })
    ] | compact

    let checks = $checks | append (
        check "migrations" ($pending | is-empty)
        "nothing to catch up on"
        "carry out each entry of `migrations`, then record it with `setup.nu migrated <id>`"
    )
    let failing = $checks | where not ok
    {
        result: (if ($failing | is-empty) { "ok" } else { "needs-attention" })
        repo: $info.nameWithOwner
        checks: $checks
        settings: $settings
        migrations: $pending
        next: (
            if ($failing | is-empty) { "start workers with spawn.nu" } else { "settle each check that is not ok, then run setup.nu again" }
        )
    }
}

def check [
    name: string
    ok: bool
    detail: string
    next: string
]: nothing -> record {
    if $ok { {name: $name, ok: true, detail: $detail} } else { {name: $name, ok: false, next: $next} }
}

# Approvals the base requires from its rulesets or its classic protection.
def required-approvals [base: string]: nothing -> int {
    let rules = ^gh api $"repos/{owner}/{repo}/rules/branches/($base)" | complete
    let from_rules = if $rules.exit_code == 0 {
        $rules.stdout | from json | where type == "pull_request" | get -o parameters.required_approving_review_count | default []
    } else { [] }
    let classic = ^gh api $"repos/{owner}/{repo}/branches/($base)/protection/required_pull_request_reviews" | complete
    let from_classic = if $classic.exit_code == 0 {
        [
            (
                $classic.stdout
                | from json
                | get -o required_approving_review_count
                | default 0
            )
        ]
    } else { [] }
    $from_rules | append $from_classic | append 0 | math max
}

# Whether commits in `repo` pick the agent signing key, which needs no Touch ID.
def signs-for-agents [repo: string]: nothing -> bool {
    let r = ^git -C $repo config --show-origin user.signingkey | complete
    $r.exit_code == 0 and ($r.stdout | str contains "ai-signing")
}

# Every migration in references/migrations.md, oldest first: a `## <id> <title>`
# heading and the steps under it.
def all-migrations []: nothing -> table {
    open --raw $migrations_file
    | split row "\n## "
    | skip 1
    | each {|sec|
        let lines = $sec | lines
        let head = $lines | first | parse --regex '^(?<id>\S+)\s+(?<title>.+)$' | first
        {id: $head.id, title: $head.title, steps: ($lines | skip 1 | str join "\n" | str trim)}
    }
}

def migrated-file [repo: string]: nothing -> string {
    state-dir $repo | path join migrated
}

def done-migrations [repo: string]: nothing -> list<string> {
    let f = migrated-file $repo
    if ($f | path exists) {
        open --raw $f | lines | where $it != ""
    } else { [] }
}

def save-done [repo: string, ids: list<string>] {
    mkdir (state-dir $repo)
    $ids | str join "\n" | save --force (migrated-file $repo)
}

# The migrations `repo` has not done. A repository the harness has never run
# in has nothing to catch up on, so its record starts with every migration.
def pending-migrations [repo: string]: nothing -> table {
    let all = all-migrations
    let dir = state-dir $repo
    let used = ($dir | path exists) and (ls $dir | where name !~ '/migrated$' | is-not-empty)
    if not (migrated-file $repo | path exists) and not $used {
        save-done $repo ($all | get id)
        return []
    }
    let done = done-migrations $repo
    $all | where id not-in $done
}
