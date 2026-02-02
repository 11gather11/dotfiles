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

# PATH setup is managed by Nix (see ~/.config/fish/conf.d/*.fish)

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :
