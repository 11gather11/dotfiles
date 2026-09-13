#!/usr/bin/env bash
# Keeps `gh pr create` behind a Codex review of the tree the PR is opened from.
#
# `run` runs `codex exec review` and, when it finishes successfully, records the
# commit that review covered. `check` refuses to open a PR from a commit with no
# such record. `check` reads the hook payload as JSON on stdin; `run` is called
# as a command (see codex-review-run in nix/lib/helpers/codex-review-gate.nix).
#
# What is recorded is a commit, not the bare fact that some review ran
# somewhere. One marker shared by every project was opened by a review in any
# of them, so a review in one repository let an unreviewed PR out of another.
# Keying on the commit also shuts the gate again once commits are added after
# the review: those commits are exactly the ones nobody has looked at.
#
# The record is written when the review ends, not when it is asked for. The
# earlier version marked on the codex-review skill being invoked, and the Skill
# tool returns at load time, so the gate opened before any review had run.
#
# The commit checked is the one the PR is opened from, not the session's
# working directory. Agents work in a worktree by prefixing `cd <worktree> &&`,
# while the hook payload's `cwd` stays on the main checkout; checking `cwd`
# compared a commit that was never being opened as a PR.
#
# What this does not stop, so that the gate is not mistaken for more than it is.
# Each of these takes knowing the gate is there and going around it, which is a
# different thing from forgetting to review:
#
#   - opening the PR through the API instead, `gh api .../pulls -f title=x`.
#   - spelling the command so the words never start a command: building it from
#     variables, `bash -c '...'`, or decoding it.
#   - writing a marker file by hand.
#   - reading the review's output and ignoring it. The marker says a review ran
#     to completion over this commit, not that it found nothing.

set -uo pipefail

mode=${1:-}
marker_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-codex-review"

# Prints the commit a ref names inside a directory, or nothing. Callers treat
# nothing as "no review".
commit_of() {
  git -C "$1" rev-parse --verify -q "$2^{commit}" 2>/dev/null
}

case "$mode" in
run)
  shift
  [ "${1:-}" = "--" ] && shift

  # Decide what this review covers before it runs: commits added while it runs
  # were not part of what it read.
  covered=""
  prev=""
  for arg in "$@"; do
    case "$prev" in
    --commit) covered=$(commit_of . "$arg") ;;
    --base) covered=$(commit_of . HEAD) ;;
    esac
    case "$arg" in
    --commit=*) covered=$(commit_of . "${arg#--commit=}") ;;
    --base=*) covered=$(commit_of . HEAD) ;;
    esac
    prev=$arg
  done

  # Closed stdin: run in the background, codex otherwise waits for more input on
  # a stdin nobody will close, and never starts.
  codex exec review "$@" </dev/null
  status=$?

  if [ "$status" -ne 0 ]; then
    exit "$status"
  fi
  if [ -z "$covered" ]; then
    # --uncommitted and a free-form prompt cover no commit a PR could be opened
    # from, so they are not a review of one.
    echo "codex-review-run: this scope covers no commit, so it does not open the PR gate. Use --base <branch> or --commit <sha>." >&2
    exit 0
  fi
  if mkdir -p "$marker_dir" && : >"$marker_dir/$covered"; then
    echo "codex-review-run: recorded a review of $covered" >&2
  fi
  # A marker older than this belongs to a tree nobody is still opening a PR for,
  # and the directory otherwise grows one file per reviewed commit.
  find "$marker_dir" -type f -mtime +30 -delete 2>/dev/null || true
  exit 0
  ;;

check)
  input=$(cat)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)

  # An unreadable payload used to be a free pass: jq printed nothing, nothing
  # matched, and the command went through with no marker anywhere. Refusing
  # outright would refuse every Bash command in the session, so the raw text is
  # searched for the words instead. Nothing below applies to it: the raw text is
  # JSON, so the command sits inside quotes, and dropping quoted text would
  # drop the command.
  if ! cmd=$(printf '%s' "$input" | jq -er '.tool_input.command' 2>/dev/null); then
    if printf '%s' "${input//\\$'\n'/}" | tr -s '[:space:]' ' ' | grep -q 'gh pr create'; then
      echo 'BLOCKED: The hook payload could not be read, and it names the PR command, so the gate stays shut.' >&2
      exit 2
    fi
    exit 0
  fi

  # Heredoc bodies are data handed to another program, not commands this shell
  # runs. A prompt that merely mentioned the words was blocked because of them.
  # Dropped line by line, before the lines are joined.
  cmd=$(printf '%s\n' "$cmd" | awk '
    in_body { if ($0 ~ "^[\t ]*" tag "[\t ]*$") in_body = 0; next }
    {
      print
      if (match($0, /<<-?[\t ]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
        tag = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[\t ]*["'\'']?/, "", tag)
        in_body = 1
      }
    }')

  # Join continued lines the way the shell does: the backslash would otherwise
  # sit between the words and keep the spelling from matching.
  cmd=${cmd//\\$'\n'/}

  # Squeeze every run of whitespace, newlines included, to one space, so that
  # the spelling is all that has to be matched afterwards.
  cmd=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')

  # A quoted path after cd is still a path: unquote it while it has no spaces,
  # before quoted text is dropped.
  cmd=$(printf '%s' "$cmd" | sed -E "s/(^|[ ;&|(])cd ([\"'])([^\"' ]+)\\2/\\1cd \\3/g")

  # Quoted text is an argument, not a command: a commit message or a prompt that
  # names the command is not the command.
  cmd=$(printf '%s' "$cmd" | sed -E "s/'[^']*'/ /g; s/\"([^\"\\\\]|\\\\.)*\"/ /g")

  # One command per line: split where the shell starts a new command.
  segments=$(printf '%s' "$cmd" | sed -E 's/&&|\|\||[;|(){}`]/\n/g')

  dir=$cwd
  found=0
  blocked=0
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" | sed -E 's/^ +//; s/ +$//')
    # Assignments and wrappers in front of a command do not change which
    # command it is.
    seg=$(printf '%s' "$seg" | sed -E ':a
s/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +|env +|command +|exec +|time +|nohup +)//
ta')

    if [[ $seg =~ ^cd\ +([^ ]+) ]]; then
      target=${BASH_REMATCH[1]}
      case "$target" in
      /*) dir=$target ;;
      *) dir="$dir/$target" ;;
      esac
      continue
    fi

    [[ $seg =~ ^gh\ +pr\ +create(\ |$) ]] || continue
    found=1

    ref=HEAD
    if [[ $seg =~ (^|\ )--head[=\ ]([^ ]+) ]]; then
      ref=${BASH_REMATCH[2]}
    fi

    sha=""
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      sha=$(commit_of "$dir" "$ref")
      [ -n "$sha" ] || sha=$(commit_of "$dir" "origin/$ref")
    fi
    if [ -z "$sha" ] || [ ! -f "$marker_dir/$sha" ]; then
      blocked=1
    fi
  done <<<"$segments"

  [ "$found" -eq 1 ] || exit 0
  [ "$blocked" -eq 0 ] && exit 0

  # Nothing is consumed on the way through: while the commit stays put the
  # review still covers the tree, and a second PR off it is as reviewed as the
  # first.
  echo 'BLOCKED: No completed Codex review covers the commit this PR would be opened from. Run "codex-review-run --base <branch>" (or "--commit <sha>") in that worktree and let it finish, then open the PR from there. If you change directory first, give cd a literal path so the gate can find the worktree.' >&2
  exit 2
  ;;
esac

exit 0
