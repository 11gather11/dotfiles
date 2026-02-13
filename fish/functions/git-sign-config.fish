function git-sign-config
    if string match -q "$HOME/work/*" (pwd)
        set -l key $GIT_SSH_KEY_WORK
    else
        set -l key $GIT_SSH_KEY
    end

    if test -z "$key"
        echo "GIT_SSH_KEY not found"
        return
    end
    git config user.signingKey "$key"
end
