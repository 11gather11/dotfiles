#!/usr/bin/env nu

# Ensure the TypeWhisper dictionary contains the custom terms and corrections
# defined in dictionary.json, via its local HTTP API.
#
# This is intentionally ADDITIVE, not a mirror. Activating a term pack
# materialises its terms and corrections into the same dictionary store this API
# exposes, and the API gives no way to tell pack-provided entries apart from
# user-defined ones. A wholesale replace would therefore wipe every activated
# term pack, so this only ever merges our own entries in and never deletes. To
# remove an entry, delete it in the app, or with an explicit DELETE request.
#
# The TypeWhisper HTTP API must be enabled in Settings > Advanced. It binds to
# 127.0.0.1 only. Override the port with $TYPEWHISPER_PORT and the bearer token
# with $TYPEWHISPER_API_TOKEN when the defaults do not match.
#
# nu is not on the interactive PATH here, so run it through a shell that has it:
#
#   nix shell nixpkgs#nushell --command ./dict-sync.nu

const DEFAULT_PORT = '8978'
const SHAPE = '{original, replacement, caseSensitive}'

# Reject a dictionary file whose shape would otherwise fail one request at a
# time, halfway through a sync.
def parse-dictionary [source: path]: nothing -> record {
    let data = (open $source)

    if not ($data | describe | str starts-with 'record') {
        error make {msg: $"($source): expected a JSON object"}
    }

    let terms = $data | get --optional terms
    if not ($terms | describe | str starts-with 'list') {
        error make {msg: $'($source): "terms" must be an array of strings'}
    }
    if ($terms | any {|term| ($term | describe) != 'string' }) {
        error make {msg: $'($source): "terms" must be an array of strings'}
    }

    # A list of uniform records describes as `table<...>`, not `list<...>`, so
    # both spellings have to be accepted: which one comes back depends only on
    # whether the entries happen to share their columns.
    let corrections = $data | get --optional corrections
    let is_sequence = {|value|
        let kind = $value | describe
        ($kind | str starts-with 'list') or ($kind | str starts-with 'table')
    }
    if not (do $is_sequence $corrections) {
        error make {msg: $'($source): "corrections" must be an array of ($SHAPE)'}
    }
    for correction in $corrections {
        let shaped = (
            ($correction | describe | str starts-with 'record')
            and ($correction | get --optional original | describe) == 'string'
            and ($correction | get --optional replacement | describe) == 'string'
            and ($correction | get --optional caseSensitive | describe) == 'bool'
        )
        if not $shaped {
            error make {msg: $'($source): "corrections" must be an array of ($SHAPE)'}
        }
    }

    {terms: $terms, corrections: $corrections}
}

# Bearer auth only when a token is configured. The value is read here and passed
# straight to the request; it is never printed or interpolated into a message.
def auth-headers []: nothing -> list<string> {
    let token = $env | get --optional TYPEWHISPER_API_TOKEN | default ''
    if ($token | is-empty) { [] } else { [Authorization $"Bearer ($token)"] }
}

def main [
    file?: path # dictionary JSON; defaults to dictionary.json beside this script
    --strict # fail when the API is unreachable instead of skipping
]: nothing -> nothing {
    let source = (
        $file
        | default ($env.FILE_PWD | path join 'dictionary.json')
        | path expand
    )
    let dict = (parse-dictionary $source)

    let port = $env | get --optional TYPEWHISPER_PORT | default $DEFAULT_PORT
    let root = $"http://localhost:($port)"
    let headers = (auth-headers)

    # Optional dependency: the app need not be running, so skip quietly unless
    # the caller asked to be told.
    let reachable = (
        try {
            http get --headers $headers $"($root)/v1/status" | ignore
            true
        } catch {
            false
        }
    )

    if not $reachable {
        let message = $"typewhisper-dict-sync: API not reachable on :($port) — enable it in Settings > Advanced"
        if $strict {
            error make {msg: $message}
        }
        print --stderr $"($message) \(skipping\)"
        return
    }

    let base = $"($root)/v1/dictionary"

    # terms: merge ours in. replace:false is what keeps term-pack terms intact.
    http put --headers $headers --content-type application/json $"($base)/terms" {
        terms: $dict.terms
        replace: false
    } | ignore

    # corrections: add or update each one. PUT is idempotent per original.
    for correction in $dict.corrections {
        http put --headers $headers --content-type application/json $"($base)/corrections" $correction | ignore
    }

    let counts = $"($dict.terms | length) terms, ($dict.corrections | length) corrections"
    print $"typewhisper-dict-sync: synced ($counts) from ($source)"
}
