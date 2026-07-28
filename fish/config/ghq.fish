# Show a shallow directory tree of the highlighted repository in the fzf
# preview pane. Falls back to plain ls when eza is unavailable.
set -x GHQ_SELECTOR_OPTS "--height 40% --reverse --preview 'eza --tree --level=2 --git-ignore --color=always --icons {} 2>/dev/null || ls {}'"
set -x GHQ_SELECTOR fzf
