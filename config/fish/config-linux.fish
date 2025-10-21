# Homebrew on Linux
if test -d /home/linuxbrew/.linuxbrew/bin
    set -gx PATH /home/linuxbrew/.linuxbrew/bin $PATH
    set -gx HOMEBREW_PREFIX "/home/linuxbrew/.linuxbrew"
    set -gx HOMEBREW_CELLAR "$HOMEBREW_PREFIX/Cellar"
    set -gx HOMEBREW_REPOSITORY "$HOMEBREW_PREFIX/Homebrew"
    set -gx MANPATH "$HOMEBREW_PREFIX/share/man" $MANPATH
    set -gx INFOPATH "$HOMEBREW_PREFIX/share/info" $INFOPATH
end

if type -q eza
  alias ll "eza -l -g --icons"
  alias lla "ll -a"
end
