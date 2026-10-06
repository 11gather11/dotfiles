function ka --description 'keep the Mac awake, lid closed included, until Ctrl+C or Ctrl+D'
    # A sleep block someone else set is theirs to lift; restoring it on exit
    # would turn their setting off.
    if pmset -g | awk '$1 == "SleepDisabled" && $2 == 1 { found = 1 } END { exit !found }'
        echo 'Sleep is already disabled; ka leaves it alone. To lift it: sudo pmset -a disablesleep 0' >&2
        return 1
    end

    # caffeinate does not stop a MacBook without an external display from
    # sleeping when its lid closes, so agents left running stop with it.
    # disablesleep does. The root shell sets the restore trap before it
    # disables sleep, so ending needs no second sudo prompt — one that could
    # have expired by then, and cancelling it would leave sleep off for good.
    sudo /bin/sh -c '
        trap "pmset -a disablesleep 0 || exit 1" EXIT
        trap "exit 130" HUP INT TERM
        pmset -a disablesleep 1 || exit
        echo "Sleep disabled. Ctrl+C or Ctrl+D restores it; do so before closing this terminal."
        while read -r _; do :; done
    '
end
