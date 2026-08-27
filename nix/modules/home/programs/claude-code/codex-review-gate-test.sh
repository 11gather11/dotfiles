#!/usr/bin/env bash
# Tests for codex-review-gate.sh. Runs as a flake check; see nix/flake/checks.nix.
#
# The first case is the one that matters: it is the failure that was actually
# observed — a review in one repository opening the gate for a PR in another.

set -uo pipefail

gate=${1:?usage: codex-review-gate-test.sh <path to codex-review-gate.sh>}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export XDG_STATE_HOME="$work/state"

failures=0

# Every commit carries distinct content. Empty commits would not do: under a
# fixed clock — which is what the sandbox this runs in provides — two repos
# committing the same empty tree with the same author and message land on the
# same SHA, and the cross-repository case would then pass for the wrong reason.
mkrepo() {
  git -C "$work" init -q "$1"
  echo "$1" >"$work/$1/marker"
  git -C "$work/$1" add marker
  git -C "$work/$1" -c user.email=t@example -c user.name=t commit -q -m "init $1"
}

commit() {
  echo "$2" >>"$work/$1/marker"
  git -C "$work/$1" add marker
  git -C "$work/$1" -c user.email=t@example -c user.name=t commit -q -m "$2"
}

mark() {
  printf '{"cwd":"%s","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "${2:-codex-review}" |
    bash "$gate" mark
}

# Echoes the exit status so a blocked call does not abort the run.
check() {
  printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "${2:-gh pr create --fill}" |
    bash "$gate" check >/dev/null 2>&1
  echo $?
}

expect() {
  local label=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    echo "ok    $label"
  else
    echo "FAIL  $label (want exit $want, got $got)"
    failures=$((failures + 1))
  fi
}

mkrepo repo_a
mkrepo repo_b
mkdir -p "$work/plain"

# The reported hole.
mark "$work/repo_a"
expect "review in one repo does not open the gate in another" 2 "$(check "$work/repo_b")"

# The gate still opens where the review actually happened.
expect "review opens the gate in the repo it ran in" 0 "$(check "$work/repo_a")"

# And it is not spent by opening: same tree, still reviewed.
expect "marker is not consumed by a passing check" 0 "$(check "$work/repo_a")"

# Commits added after the review are the unreviewed ones.
commit repo_a later
expect "a commit added after the review shuts the gate" 2 "$(check "$work/repo_a")"

# Fail closed rather than falling back to a marker every project shares.
expect "a cwd that is not a repository is refused" 2 "$(check "$work/plain")"

# Only codex-review may open it.
mkrepo repo_c
mark "$work/repo_c" some-other-skill
expect "another skill does not open the gate" 2 "$(check "$work/repo_c")"

# The gate must stay out of the way of every other Bash command.
expect "an unrelated command is untouched" 0 "$(check "$work/repo_b" "git status")"

echo
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
