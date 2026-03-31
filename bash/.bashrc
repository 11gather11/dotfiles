export LC_ALL='en_US.UTF-8'
##export LANG=ja_JP.UTF-8
export BASH_SILENCE_DEPRECATION_WARNING=1


export EDITOR=nvim

export ARCH=$(uname -m)

# PATH
export XDG_CONFIG_HOME="$HOME/.config"

# brew
export HOMEBREW_BUNDLE_FILE="$HOME/.Brewfile"
export HOMEBREW_NO_ANALYTICS=1

# direnv
eval "$(direnv hook bash)"

# nix
if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# home-manager session variables
HM_SESSION_VARS="$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"
if [ -f "$HM_SESSION_VARS" ]; then
    . "$HM_SESSION_VARS"
fi

if [[ -t 0 ]]; then
    stty stop undef
    stty start undef
fi
