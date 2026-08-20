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

    # Refuse a destination outside the repository. The typed path goes through
    # unchanged, so ../.. reaches anywhere the shell can write, and the prompt
    # offers to create it.
    set -l dest (path normalize "$base/$rel")
    if not string match -q -- "$base/*" "$dest/"
        echo "dlmv: $rel is outside $base" >&2
        return 1
    end
    mkdir -p "$dest"; or return 1

    set -l shown (string replace "$base/" '' "$dest")
    for f in $picked
        set -l src "$HOME/Downloads/$f"
        set -l name (path basename "$f")

        if not test -e "$dest/$name"
            if not command mv -- "$src" "$dest/$name"
                echo "dlmv: could not move $name" >&2
                continue
            end
            echo "→ $shown/$name"
            continue
        end

        # A collision here is usually the same spreadsheet downloaded again, so
        # the useful answers are three, not the two `mv -i` offers. Keeping both
        # is the default because it is the only one that neither destroys the
        # copy already filed nor leaves the download where it was.
        read -l -P "$shown/$name exists — [o]verwrite / [K]eep both / [s]kip? " reply
        switch (string lower -- (string trim -- "$reply"))
            case o overwrite
                if not command mv -f -- "$src" "$dest/$name"
                    echo "dlmv: could not replace $shown/$name" >&2
                    continue
                end
                echo "→ $shown/$name (replaced)"
            case s skip
                echo "left in ~/Downloads: $name"
            case '*'
                # -2, -3, … before the extension: predictable, and it does not
                # collide with the .orig convention already used in these
                # directories for a file kept deliberately.
                set -l stem (path change-extension '' "$name")
                set -l ext (path extension "$name")
                set -l n 2
                while test -e "$dest/$stem-$n$ext"
                    set n (math $n + 1)
                end
                if not command mv -- "$src" "$dest/$stem-$n$ext"
                    echo "dlmv: could not move $name" >&2
                    continue
                end
                echo "→ $shown/$stem-$n$ext"
        end
    end
end
