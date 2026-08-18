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

# Put the home-manager profile ahead of /usr/bin, the way fish already has it.
#
# A login shell started from an empty environment gets this ordering for free:
# path_helper builds PATH from /etc/paths and /etc/paths.d, and nix-darwin
# registers the Nix profiles there. A login shell started from an environment
# that already has a PATH does not — path_helper puts /etc/paths first and
# appends what it inherited, which pushes the profile behind /usr/bin. That is
# exactly how agents spawn `bash -lc`, and it is why `git` resolved to Apple's
# 2.50.1 there while fish and this configuration's own tools resolved to 2.55.0.
#
# Drop any existing occurrence before prepending so repeated sourcing does not
# grow PATH.
# /etc/profiles/per-user is where useUserPackages puts the profile, so it is the
# supported path. The gcroots one is home-manager's own bookkeeping — a symlink
# into a home-manager-generation store path — and is here only for standalone
# home-manager, which has no /etc/profiles.
HM_BIN="/etc/profiles/per-user/$USER/bin"
if [ ! -d "$HM_BIN" ]; then
  HM_BIN="$HOME/.local/state/home-manager/gcroots/current-home/home-path/bin"
fi
if [ -d "$HM_BIN" ]; then
  PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$HM_BIN" | paste -sd: -)"
  export PATH="$HM_BIN:$PATH"
fi
unset HM_BIN

if [[ -t 0 ]]; then
  stty stop undef
  stty start undef
fi
