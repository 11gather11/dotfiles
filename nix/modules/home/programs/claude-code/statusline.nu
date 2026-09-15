# Claude Code statusline: the model with its effort level, how much of the
# context window has been used, and how much of the five-hour and weekly rate
# limits is left. Claude Code passes the session state as JSON on stdin.

const RESET = "\e[0m"
const DIM = "\e[2m"

# Truecolour foreground for a usage percentage: green shading to orange up to
# 50%, then orange shading to red.
def gradient [pct: number]: nothing -> string {
    if $pct < 50 {
        $"\e[38;2;($pct * 5.1 | math floor);200;80m"
    } else {
        $"\e[38;2;255;([(200 - ($pct - 50) * 4 | math floor) 0] | math max);60m"
    }
}

# "<label> <n>% used", or with --left "<label> <n>% left". The number is
# coloured by how much is used either way, so a limit running out turns red.
def meter [label: string, used: number, --left]: nothing -> string {
    let shown = if $left { 100 - $used } else { $used }
    let word = if $left { "left" } else { "used" }
    $"($label) (gradient $used)($shown | math round)%($RESET) ($word)"
}

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
    let meters = [
        [label, used, left];
        ["Context", $state.context_window?.used_percentage?, false]
        ["5h", $state.rate_limits?.five_hour?.used_percentage?, true]
        ["weekly", $state.rate_limits?.seven_day?.used_percentage?, true]
    ]
    | where used != null
    | each {|m| meter $m.label $m.used --left=$m.left }

    [$model ...$meters]
    | each { $" ($in) " }
    | str join $"($DIM)·($RESET)"
    | print --no-newline
}
