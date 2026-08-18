function ghq-work --description 'ghq for work repositories, rooted at ~/ghq-work'
    # $HOME rather than ~: fish expands a tilde only at the start of a word, so
    # `GHQ_ROOT=~/…` passed ghq the literal string, which ghq then resolved as a
    # relative path. That is how the work tree ended up inside a directory
    # actually named `~`.
    env GHQ_ROOT=$HOME/ghq-work ghq $argv
end
