export LC_ALL='en_US.UTF-8'
export BASH_SILENCE_DEPRECATION_WARNING=1

export EDITOR=nvim
export XDG_CONFIG_HOME="$HOME/.config"

# Homebrew's own prefix. Everything else on PATH arrives through nix-daemon.sh
# and hm-session-vars.sh below, which is why there is no list of language
# manager bin directories here any more.
export PATH="/opt/homebrew/bin:$PATH"

# zoxide and direnv are installed as packages, not through their home-manager
# modules, and programs.bash is not enabled — so nothing else sets these hooks
# up for bash. Removing either one removes the feature from this shell.
eval "$(zoxide init bash)"
eval "$(direnv hook bash)"

# man pager
if command -v nvim &> /dev/null; then
    export MANPAGER="nvim -c ASMANPAGER -"
fi

# nix
if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# home-manager session variables.
# Prefer the standalone home-manager gcroots (Linux / `home-manager switch`),
# falling back to the nix-darwin module profile (`/etc/profiles/per-user`).
HM_SESSION_VARS="$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"
if [ ! -f "$HM_SESSION_VARS" ]; then
  HM_SESSION_VARS="/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
fi
if [ -f "$HM_SESSION_VARS" ]; then
  # An ancestor process may already have marked these as sourced, which would
  # make the script a no-op in agent-spawned shells. Clear the guard so the
  # variables are applied here regardless.
  unset __HM_SESS_VARS_SOURCED
  . "$HM_SESSION_VARS"
fi

if [[ -t 0 ]]; then
  stty stop undef
  stty start undef
fi
