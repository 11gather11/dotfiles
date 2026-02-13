set -gx LC_ALL "en_US.UTF-8"
set -gx BASH_SILENCE_DEPRECATION_WARNING 1

# define XDG paths
set -q XDG_CONFIG_HOME || set -gx XDG_CONFIG_HOME $HOME/.config
set -q XDG_DATA_HOME || set -gx XDG_DATA_HOME $HOME/.local/share
set -q XDG_CACHE_HOME || set -gx XDG_CACHE_HOME $HOME/.cache

# Source home-manager session variables
set -l HM_SESSION_VARS "$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"
if test -f $HM_SESSION_VARS
    for line in (grep '^export ' $HM_SESSION_VARS)
        set -l kv (string replace 'export ' '' $line)
        set -l key (string split -m1 '=' $kv)[1]
        set -l value (string split -m1 '=' $kv)[2]
        # Remove surrounding quotes if present
        set value (string trim -c '"' $value)
        set -gx $key $value
    end
end

# define fish config paths
set -g FISH_CONFIG_DIR $XDG_CONFIG_HOME/fish
set -g FISH_CONFIG $FISH_CONFIG_DIR/config.fish
set -g FISH_CACHE_DIR /tmp/fish-cache

# load user config (functions/ is auto-loaded by Fish)
for file in $FISH_CONFIG_DIR/config/*.fish
    source $file &
end

# theme
set -gx theme_nerd_fonts yes
set -gx BIT_THEME monochrome
source $FISH_CONFIG_DIR/themes/kanagawa.fish

# general bin paths
fish_add_path $HOME/.local/bin
fish_add_path /usr/local/opt/coreutils/libexec/gnubin
fish_add_path /usr/local/opt/curl/bin

# brew
fish_add_path /opt/homebrew/bin

# js/ts
## bun
fish_add_path $HOME/.bun/bin
fish_add_path $HOME/.cache/.bun/bin

# anyenv
if type -q anyenv
    status --is-interactive; and source (anyenv init - fish | psub)
end

# go
set -gx GOPATH $HOME/go
fish_add_path $GOPATH/bin

# user scripts
fish_add_path $HOME/.scripts
fish_add_path $HOME/.scripts/bin

# wezterm
fish_add_path /Applications/WezTerm.app/Contents/MacOS

# 1Password SSH Agent
set _1P_SSH_SOCK "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
test -e $_1P_SSH_SOCK && set -x SSH_AUTH_SOCK $_1P_SSH_SOCK

set -l CONFIG_CACHE $FISH_CACHE_DIR/config.fish
if not test -f "$CONFIG_CACHE"; or test "$FISH_CONFIG" -nt "$CONFIG_CACHE"
    mkdir -p $FISH_CACHE_DIR
    echo '' >$CONFIG_CACHE

    # homebrew
    if test (uname -m) = arm64
        echo $(/opt/homebrew/bin/brew shellenv) >>$CONFIG_CACHE
        echo "set -gx PATH /opt/homebrew/opt/llvm/bin $PATH" >>$CONFIG_CACHE
    else
        echo $(/usr/local/bin/brew shellenv) >>$CONFIG_CACHE
    end

    # xcode
    echo "fish_add_path $(ensure_installed xcode-select -p)/usr/bin" >>$CONFIG_CACHE
    echo "set -gx SDKROOT $(ensure_installed xcrun --sdk macosx --show-sdk-path)" >>$CONFIG_CACHE

    # ruby
    echo "fish_add_path $(ensure_installed brew --prefix)/opt/ruby/bin" >>$CONFIG_CACHE
    echo "fish_add_path $(ensure_installed gem environment gemdir)/bin" >>$CONFIG_CACHE

    # tools
    ensure_installed direnv hook fish >>$CONFIG_CACHE
    ensure_installed zoxide init fish >>$CONFIG_CACHE
    # starship init fish >>$CONFIG_CACHE

    # set vivid colors
    echo "set -gx LS_COLORS '$(ensure_installed vivid generate gruvbox-dark)'" >>$CONFIG_CACHE

    # jj
    ensure_installed jj util completion fish >>$CONFIG_CACHE

    set_color brmagenta --bold --underline
    echo "config cache updated"
    set_color normal
end
source $CONFIG_CACHE

# neovim
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
set -gx VISUAL nvim
set -gx MANPAGER "nvim -c ASMANPAGER -"

if status is-interactive
    stty stop undef &
    stty start undef &
end

set -g NA_PACKAGE_MANAGER_LIST bun deno pnpm npm yarn
set -g NA_FUZZYFINDER_OPTIONS --bind 'one:accept' --query '^'
