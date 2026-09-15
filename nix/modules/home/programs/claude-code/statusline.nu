# Claude Code statusline: the model with its effort level, how much of the
# context window has been used, and how much of the five-hour and weekly rate
# limits is left. Claude Code passes the session state as JSON on stdin.

const WIDTH = 10

# The glyph for a cell filled by 0 to 7 eighths. An empty cell is the same
# shade as the unfilled track, so a fill ending on a cell boundary leaves no
# gap inside the bar.
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
const CURSOR = "\e[1;38;2;255;255;255m"

def clamp [low: number, high: number]: number -> number {
    [$in $low] | math max | [$in $high] | math min
}

# Truecolour foreground for a usage percentage: green shading to orange up to
# 50%, then orange shading to red.
def gradient [pct: number]: nothing -> string {
    if $pct < 50 {
        let red = $pct * 5.1 | math floor
        $"\e[38;2;($red);200;80m"
    } else {
        let green = 200 - ($pct - 50) * 4 | math floor | clamp 0 255
        $"\e[38;2;255;($green);60m"
    }
}

# A WIDTH-cell bar filled to used%, with eighth-cell resolution and a dim
# track. When cursor is a percentage, the cell there is replaced by a white │.
def bar [used: number, cursor: oneof<number, nothing>]: nothing -> string {
    let color = gradient $used
    let filled = ($used | clamp 0 100) * $WIDTH / 100
    # Whole cells, then the fraction of the next cell in eighths.
    let full = $filled | math floor
    let eighths = ($filled - $full) * 8 | math floor
    let at = if $cursor == null { -1 } else {
        $cursor * $WIDTH / 100 | math floor | clamp 0 ($WIDTH - 1)
    }

    0..<$WIDTH
    | each {|i|
        match $i {
            $c if $c == $at => $"($CURSOR)│($RESET)($color)"
            $c if $c < $full => "█"
            $c if $c == $full and $eighths > 0 => ($EIGHTHS | get $eighths)
            _ => $"($DIM)░($RESET)($color)"
        }
    }
    | str join
}

# How far through its window a rate limit is, as a percentage, from the time
# it resets. Nothing when the reset time is not reported.
def elapsed [resets_at: oneof<int, nothing>, window: duration]: nothing -> oneof<number, nothing> {
    if $resets_at == null { return null }
    let reset = $resets_at * 1_000_000_000 | into datetime
    let left = $reset - (date now)
    100 - $left / $window * 100 | clamp 0 100
}

# "<label> <bar> <n>% <word>". The bar and number are coloured by the share
# used, whether the number shown is that share or the share left.
def meter [
    label: string
    used: number
    shown: number
    word: string
    cursor: oneof<number, nothing>
]: nothing -> string {
    let number = $shown | math round
    $"($label) (gradient $used)(bar $used $cursor) ($number)%($RESET) ($word)"
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
    let context = $state.context_window?.used_percentage?
    let five_hour = $state.rate_limits?.five_hour?.used_percentage?
    let weekly = $state.rate_limits?.seven_day?.used_percentage?

    [
        $model
        (if $context != null { meter "Context" $context $context "used" null })
        # Rate limits arrive as the share used and are shown as the share left,
        # with a cursor at how far through its window each one is.
        (if $five_hour != null {
            let cursor = elapsed $state.rate_limits.five_hour.resets_at? 5hr
            meter "5h" $five_hour (100 - $five_hour) "left" $cursor
        })
        (if $weekly != null {
            let cursor = elapsed $state.rate_limits.seven_day.resets_at? 7day
            meter "weekly" $weekly (100 - $weekly) "left" $cursor
        })
    ]
    | compact
    | each { $" ($in) " }
    | str join $"($DIM)·($RESET)"
    | print --no-newline
}
