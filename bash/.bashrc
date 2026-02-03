export LC_ALL='en_US.UTF-8'
##export LANG=ja_JP.UTF-8
export BASH_SILENCE_DEPRECATION_WARNING=1


export EDITOR=nvim

export ARCH=$(uname -m)

# PATH
export XDG_CONFIG_HOME="$HOME/.config"

# cargo (only if installed via rustup, not Nix)
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

# Homebrew
if [[ $ARCH == arm64 ]]; then
    eval $(/opt/homebrew/bin/brew shellenv)
elif [[ $ARCH == x86_64 ]]; then
    eval $(/usr/local/bin/brew shellenv)
fi

# anyenv
if command -v anyenv &> /dev/null; then
    eval "$(anyenv init -)"
fi

# golang
export GOPATH=~/go
export PATH=$GOPATH/bin:$PATH
export GOROOT=$(go1.24.6 env GOROOT)
export PATH=$GOROOT/bin:$PATH

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
