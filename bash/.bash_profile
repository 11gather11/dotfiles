if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Enter the project dev environment in login shells spawned by agents, which
# never reach the interactive direnv hook. zsh does not need a branch here —
# zsh/zshenv runs for every zsh invocation, interactive or not, and does this
# already; this file is only reached from zshrc, which is interactive-only.
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv export bash)"
fi

