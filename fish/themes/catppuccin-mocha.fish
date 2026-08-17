# Catppuccin Mocha Fish shell theme
# Palette: https://github.com/catppuccin/catppuccin#-palettes
# Same structure as the Kanagawa theme this replaced, so only the hex values
# below need changing to move to another Catppuccin flavour.
set -l foreground CDD6F4 # text
set -l selection 45475A # surface1
set -l comment 6C7086 # overlay0
set -l red F38BA8
set -l orange FAB387 # peach
set -l yellow F9E2AF
set -l green A6E3A1
set -l purple CBA6F7 # mauve
set -l cyan 94E2D5 # teal
set -l pink F5C2E7

# Syntax Highlighting Colors
set -g fish_color_normal $foreground
set -g fish_color_command $cyan
set -g fish_color_keyword $pink
set -g fish_color_quote $yellow
set -g fish_color_redirection $foreground
set -g fish_color_end $orange
set -g fish_color_error $red
set -g fish_color_param $purple
set -g fish_color_comment $comment
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $green
set -g fish_color_escape $pink
set -g fish_color_autosuggestion $comment

# Completion Pager Colors
set -g fish_pager_color_progress $comment
set -g fish_pager_color_prefix $cyan
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $comment
