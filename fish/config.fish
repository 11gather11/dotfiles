set -gx LC_ALL "en_US.UTF-8"
set -gx BASH_SILENCE_DEPRECATION_WARNING 1

# define XDG paths
set -q XDG_CONFIG_HOME || set -gx XDG_CONFIG_HOME $HOME/.config
set -q XDG_DATA_HOME || set -gx XDG_DATA_HOME $HOME/.local/share
set -q XDG_CACHE_HOME || set -gx XDG_CACHE_HOME $HOME/.cache

# Source home-manager session variables.
# Prefer the standalone home-manager gcroots (Linux / `home-manager switch`),
# falling back to the nix-darwin module profile (`/etc/profiles/per-user`), so
# non-interactive login shells spawned by agents still pick up the environment.
set -l HM_SESSION_VARS "$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"
if not test -f $HM_SESSION_VARS
    set HM_SESSION_VARS "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
end
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

# hm-session-vars.sh contains `export TERM="$TERM"` which the naive parser
# above reassigns as the literal `$TERM`. Fix it up here.
if test "$TERM" = '$TERM'
    set -gx TERM xterm-ghostty
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
source $FISH_CONFIG_DIR/themes/catppuccin-mocha.fish

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

# go
set -gx GOPATH $HOME/go
fish_add_path $GOPATH/bin

# user scripts
fish_add_path $HOME/.scripts
fish_add_path $HOME/.scripts/bin

# Add home-manager packages to PATH.
# Prefer the standalone home-manager gcroots (Linux / `home-manager switch`),
# falling back to the nix-darwin module profile (`/etc/profiles/per-user`).
set -l HM_PATH_BIN "$HOME/.local/state/home-manager/gcroots/current-home/home-path/bin"
if not test -d $HM_PATH_BIN
    set HM_PATH_BIN "/etc/profiles/per-user/$USER/bin"
end
fish_add_path $HM_PATH_BIN

# 1Password SSH Agent
set _1P_SSH_SOCK "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
test -e $_1P_SSH_SOCK && set -x SSH_AUTH_SOCK $_1P_SSH_SOCK

set -l CONFIG_CACHE $FISH_CACHE_DIR/config.fish
if not test -f "$CONFIG_CACHE"; or test "$FISH_CONFIG" -nt "$CONFIG_CACHE"
    mkdir -p $FISH_CACHE_DIR

    # Build the cache in a per-process temp file and only swap it into place
    # once it is fully written. Appending directly to $CONFIG_CACHE means an
    # interrupted shell (closed/killed mid-generation) leaves a truncated cache
    # that every later shell keeps sourcing — silently dropping direnv/zoxide/etc.
    # Writing to $CONFIG_CACHE_TMP then `mv` makes the swap atomic, so a partial
    # build never poisons the real cache.
    set -l CONFIG_CACHE_TMP $CONFIG_CACHE.tmp.$fish_pid
    echo '' >$CONFIG_CACHE_TMP

    # homebrew
    if test (uname -m) = arm64
        echo $(/opt/homebrew/bin/brew shellenv) >>$CONFIG_CACHE_TMP
        echo "set -gx PATH /opt/homebrew/opt/llvm/bin $PATH" >>$CONFIG_CACHE_TMP
    else
        echo $(/usr/local/bin/brew shellenv) >>$CONFIG_CACHE_TMP
    end

    # xcode
    # Append (and keep) Xcode's bin at the end of fish_user_paths so its
    # bundled tools (git, etc.) never shadow the Nix/home-manager ones
    echo "fish_add_path --append --move $(ensure_installed xcode-select -p)/usr/bin" >>$CONFIG_CACHE_TMP
    echo "set -gx SDKROOT $(ensure_installed xcrun --sdk macosx --show-sdk-path)" >>$CONFIG_CACHE_TMP

    # ruby
    echo "fish_add_path $(ensure_installed brew --prefix)/opt/ruby/bin" >>$CONFIG_CACHE_TMP
    echo "fish_add_path $(ensure_installed gem environment gemdir)/bin" >>$CONFIG_CACHE_TMP

    # tools
    ensure_installed direnv hook fish >>$CONFIG_CACHE_TMP
    ensure_installed zoxide init fish >>$CONFIG_CACHE_TMP
    ensure_installed tirith init --shell fish >>$CONFIG_CACHE_TMP
    ensure_installed git-wt --init fish >>$CONFIG_CACHE_TMP
    ensure_installed git-wtpr --init fish >>$CONFIG_CACHE_TMP
    ensure_installed starship init fish >>$CONFIG_CACHE_TMP

    # set vivid colors
    echo "set -gx LS_COLORS '$(ensure_installed vivid generate catppuccin-mocha)'" >>$CONFIG_CACHE_TMP

    mv $CONFIG_CACHE_TMP $CONFIG_CACHE

    set_color brmagenta --bold --underline
    echo "config cache updated"
    set_color normal
end
source $CONFIG_CACHE

# The cached direnv hook only fires on interactive prompts, so agent-spawned
# non-interactive login shells would never enter the project dev environment.
# Export it directly there, leaving the interactive hook untouched.
if not status is-interactive; and command -q direnv
    direnv export fish | source
end

# neovim
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
set -gx VISUAL nvim
set -gx MANPAGER "nvim -c ASMANPAGER -"

if status is-interactive
    stty stop undef &
    stty start undef &
end

set -g NA_PACKAGE_MANAGER_LIST bun pnpm npm yarn
set -g NA_FUZZYFINDER_OPTIONS --bind 'one:accept' --query '^'
