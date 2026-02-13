function gh --wraps gh --description 'gh with directory-based account switching'
    if set -q GH_WORK_ACCOUNT; and string match -q "$HOME/work/*" (pwd)
        set -lx GH_TOKEN (command gh auth token --user $GH_WORK_ACCOUNT 2>/dev/null)
    end
    command gh $argv
end
