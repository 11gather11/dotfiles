#!/usr/bin/env nu

# Import the TypeWhisper configuration in settings.json (workflows, hotkeys,
# plugins, general preferences) via its local HTTP API, so a fresh Mac ends up
# with the same setup.
#
# settings.json is a /v1/settings/export backup with three things removed:
#
# - history, which is private dictation text and must never be committed;
# - dictionaryEntries, which dict-sync.nu owns, and which an export mixes with
#   term-pack entries that cannot be told apart from our own;
# - the workflow instruction, which lives in dictation-instruction.md so the
#   prompt stays readable and diffable. It is spliced back in at import time.
#
# Import runs in "replace" mode: workflows with the same name are overwritten,
# so editing the prompt and re-running this updates the app. Nothing is deleted.
#
# The backup format deliberately omits secrets and per-machine selections. The
# ChatGPT login has to be imported once in the app (OpenAI / ChatGPT > Codex
# ログインをインポート), and the engine and Qwen3 model choice are set by
# nix/modules/darwin-system/defaults.nix.
#
# The TypeWhisper HTTP API must be enabled in Settings > Advanced. The port and
# bearer token come from $TYPEWHISPER_PORT and $TYPEWHISPER_API_TOKEN, falling
# back to the api-discovery.json the running app writes.
#
#   nix shell nixpkgs#nushell --command ./settings-sync.nu

const WORKFLOW = '開発用音声入力'
const DISCOVERY = '~/Library/Application Support/TypeWhisper/api-discovery.json'

# Strip the leading <!-- --> maintainer note so only the prompt reaches the LLM.
def read-instruction [source: path]: nothing -> string {
    open --raw $source
    | str replace --regex '(?s)^<!--.*?-->\s*' ''
    | str trim
}

def with-instruction [instruction: string]: record -> record {
    let backup = $in
    if not ($backup.workflows | any {|workflow| $workflow.name == $WORKFLOW }) {
        error make {msg: $"settings.json has no workflow named ($WORKFLOW)"}
    }
    $backup | update workflows {|row|
        $row.workflows | each {|workflow|
            if $workflow.name == $WORKFLOW {
                $workflow | upsert behavior.settings.instruction $instruction
            } else {
                $workflow
            }
        }
    }
}

# Environment first, then the running app's discovery file. The token is passed
# straight to the request and never printed.
def connection []: nothing -> record<port: string, headers: list<string>> {
    let discovery = (
        try { open ($DISCOVERY | path expand) } catch { {} }
    )
    let port = (
        $env | get --optional TYPEWHISPER_PORT
        | default ($discovery | get --optional port)
        | default 8978
        | into string
    )
    let token = (
        $env | get --optional TYPEWHISPER_API_TOKEN
        | default ($discovery | get --optional token)
        | default ''
    )
    let headers = if ($token | is-empty) { [] } else { [Authorization $"Bearer ($token)"] }
    {port: $port, headers: $headers}
}

def main [
    --strict # fail when the API is unreachable instead of skipping
]: nothing -> nothing {
    let here = $env.FILE_PWD
    let instruction = read-instruction ($here | path join 'dictation-instruction.md')
    let backup = (
        open ($here | path join 'settings.json')
        | with-instruction $instruction
        # The importer requires an export timestamp; the committed file omits it
        # so that re-exporting does not churn the diff.
        | insert exportedAt (date now | date to-timezone UTC | format date '%Y-%m-%dT%H:%M:%SZ')
    )

    let api = (connection)
    let root = $"http://127.0.0.1:($api.port)"

    let reachable = (
        try {
            http get --headers $api.headers $"($root)/v1/status" | ignore
            true
        } catch {
            false
        }
    )
    if not $reachable {
        let message = $"typewhisper-settings-sync: API not reachable on :($api.port) — enable it in Settings > Advanced"
        if $strict {
            error make {msg: $message}
        }
        print --stderr $"($message) \(skipping\)"
        return
    }

    let result = (
        http post --headers $api.headers --content-type application/json $"($root)/v1/settings/import?mode=replace" ($backup | to json --raw)
    )
    let summary = (
        $result
        | select workflowsImported workflowsUpdated workflowsSkipped hotkeysApplied pluginsInstalled pluginsSkipped preferencesApplied
        | to nuon
    )
    print $"typewhisper-settings-sync: ($summary)"
}
