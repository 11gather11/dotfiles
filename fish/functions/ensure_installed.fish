function ensure_installed -d "ensure the command is on PATH"
    set -l cmd $argv[1]
    if type -q $cmd
        $cmd $argv[2..-1]

        # Guarantee a trailing newline. Callers append this output to the
        # generated config cache, which is then sourced, and a tool whose init
        # omits its final newline (starship does) leaves the next appended line
        # glued onto its own — producing one corrupt line instead of two valid
        # ones. Harmless where the caller uses command substitution, which
        # strips trailing newlines anyway.
        echo
        return 0
    end

    # stderr, never stdout: on stdout this message becomes the line
    # `command <cmd> not found` inside that same cache, and fish runs it as a
    # command in every later shell — so a tool merely missing at generation
    # time turns into a startup error that outlives its own cause.
    echo "command $cmd not found" >&2
    return 0
end
