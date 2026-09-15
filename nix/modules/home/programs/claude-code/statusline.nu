# Claude Code statusline: the model with its effort level, how much of the
# context window has been used, and how much of the five-hour and weekly rate
# limits is left. Claude Code passes the session state as JSON on stdin.
#
# Laid out and coloured like Codex's own status line, so the two agents read
# the same side by side. The colours are the ones Codex emits.

const RESET = "\e[0m"
const DIM = "\e[2m"
const MODEL = "\e[38;2;246;226;183m"
const CONTEXT = "\e[38;2;242;181;144m"
const LIMIT = "\e[38;2;233;144;169m"

def main []: string -> nothing {
    let state = $in | from json
    # The model, then its effort level and whether fast mode is on, each only
    # when Claude Code reports it.
    let model = [
        ($state.model?.display_name? | default "Claude")
        $state.effort?.level?
        (if $state.fast_mode? == true { "fast" })
    ]
    | compact
    | str join " "
    let context = $state.context_window?.used_percentage?
    let five_hour = $state.rate_limits?.five_hour?.used_percentage?
    let weekly = $state.rate_limits?.seven_day?.used_percentage?

    [
        $"($MODEL)($model)($RESET)"
        (
            if $context != null { $"($CONTEXT)Context ($context | math round)% used($RESET)" }
        )
        # Rate limits arrive as the share used; shown as the share left.
        (
            if $five_hour != null { $"($LIMIT)5h (100 - $five_hour | math round)% left($RESET)" }
        )
        (
            if $weekly != null { $"($LIMIT)weekly (100 - $weekly | math round)% left($RESET)" }
        )
    ]
    | compact
    | each { $" ($in) " }
    | str join $"($DIM)·($RESET)"
    | print --no-newline
}
