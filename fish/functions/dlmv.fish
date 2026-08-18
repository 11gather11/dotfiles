# Sort paths newest-first, reading them from stdin and printing them back.
#
# `path mtime` rather than stat: the stat first on PATH is GNU coreutils from
# the Nix profile, where -f asks for filesystem information rather than a format
# string, so the BSD spelling this used to carry printed inode counts instead of
# timestamps. path mtime is a fish builtin and needs neither.
function _dlmv_newest_first --argument-names base
    set -l rels
    while read -l line
        set -a rels $line
    end
    test (count $rels) -gt 0; or return 0

    set -l full
    for r in $rels
        set -a full (path normalize "$base/$r")
    end
    set -l times (path mtime -- $full)

    for i in (seq (count $rels))
        printf '%s\t%s\n' $times[$i] $rels[$i]
    end | sort -rn | cut -f2-
end

function dlmv --description 'pick a download, pick where it goes, move it'
    set -l picked (
        fd --type f --base-directory ~/Downloads \
        | _dlmv_newest_first ~/Downloads \
        | fzf --multi --height 40% --reverse --prompt 'download> '
    )
    test -n "$picked"; or return 0

    # Offer the whole repository rather than the current directory, so this
    # works from anywhere in a checkout without cd-ing first. --no-ignore and
    # --hidden because the directories these files belong in are .works/*, which
    # is both dotted and gitignored — the two reasons fd would skip them.
    set -l base (command git rev-parse --show-toplevel 2>/dev/null)
    test -n "$base"; or set base (pwd)

    set -l choice (
        begin
            printf '.\n'
            fd --type d --hidden --no-ignore --base-directory "$base" \
                --exclude .git --exclude node_modules --exclude .direnv \
                --exclude .venv --exclude target --exclude dist \
                --exclude .next --exclude .turbo --exclude .cache --exclude coverage \
            | _dlmv_newest_first "$base"
        end \
        | fzf --height 40% --reverse --print-query \
            --prompt 'destination> ' \
            --preview "command ls -1 '$base'/{} 2>/dev/null | head -20"
    )
    test -n "$choice"; or return 0

    # --print-query puts the typed text first and the selection, if any, second.
    # With no selection the typed text is a directory that does not exist yet,
    # which is the normal case when starting a task.
    set -l rel
    if test (count $choice) -ge 2
        set rel $choice[2]
    else
        read -l -P "$choice[1] does not exist. create it? [y/N] " reply
        string match -qi 'y*' -- $reply; or return 1
        set rel $choice[1]
    end

    set -l dest (path normalize "$base/$rel")
    mkdir -p "$dest"; or return 1

    for f in $picked
        # -i rather than -f: a download that collides with a file already in the
        # task directory is usually a second copy of it, and picking which one
        # survives is not a decision to make silently.
        mv -i -- "$HOME/Downloads/$f" "$dest"; or return 1
        echo "→ "(string replace "$base/" '' "$dest")"/"(path basename "$f")
    end
end
