function gh --wraps gh --description 'gh, run as the account that owns the tree you are in'
    # Name the account in both directions. gh otherwise uses whichever account
    # is active, and the active one is not necessarily the personal one, so
    # leaving the personal case unhandled meant personal repositories were
    # operated on as the work account.
    #
    # The work account is read from ~/.gitconfig.work rather than written here:
    # this repository is public, so naming it would publish it. The personal
    # account is this repository's own git identity, which is already public.
    set -l account
    if string match -q "$HOME/ghq-work/*" (pwd)
        set account (command git config --file ~/.gitconfig.work --get user.name 2>/dev/null)
        if test -z "$account"
            echo "gh: no work account in ~/.gitconfig.work" >&2
            return 1
        end
    else
        set account (command git config --global --get user.name 2>/dev/null)
    end

    if test -n "$account"
        set -l token (command gh auth token --user $account 2>/dev/null)
        test -n "$token"; and set -fx GH_TOKEN $token
    end
    command gh $argv
end
