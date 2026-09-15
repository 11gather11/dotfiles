# Claude Code statusline: the model, and how much of the context window and
# of the five-hour and seven-day rate limits has been used. Claude Code passes
# the session state as JSON on stdin.

const WIDTH = 10

# The glyph for a cell filled by 0 to 7 eighths. An empty cell is the same
# shade as the unfilled track; a blank there left a gap inside the bar
# whenever the fill landed exactly on a cell boundary.
const EIGHTHS = [
    "░"
    "▏"
    "▎"
    "▍"
    "▌"
    "▋"
    "▊"
    "▉"
]

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

# A WIDTH-cell bar filled to pct, with eighth-cell resolution.
def bar [pct: number]: nothing -> string {
    let clamped = [
        ([$pct 0] | math max)
        100
    ] | math min
    let filled = $clamped * $WIDTH / 100
    # Whole cells, then the fraction of the next cell in eighths.
    let full = $filled | math floor
    let eighths = ($filled - $full) * 8 | math floor
    let rest = match ($WIDTH - $full) {
        0 => []
        $empty => [
            ($EIGHTHS | get $eighths)
            ...(1..<$empty | each { "░" })
        ]
    }
    [
        ...(0..<$full | each { "█" })
        ...$rest
    ] | str join
}

def meter [label: string, pct: number]: nothing -> string {
    $"($label) (gradient $pct)(bar $pct) ($pct | math round)%($RESET)"
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
        [label, pct];
        ["ctx", $state.context_window?.used_percentage?]
        ["5h", $state.rate_limits?.five_hour?.used_percentage?]
        ["7d", $state.rate_limits?.seven_day?.used_percentage?]
    ]
    | where pct != null
    | each {|m| meter $m.label $m.pct }

    [$model ...$meters]
    | each { $" ($in) " }
    | str join $"($DIM)│($RESET)"
    | print --no-newline
}
