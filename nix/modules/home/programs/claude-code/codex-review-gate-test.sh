#!/usr/bin/env bash
# Tests for codex-review-gate.sh. Runs as a flake check; see nix/flake/checks.nix.
#
# The first case is the one that matters most: it is the failure that was
# actually observed first — a review in one repository opening the gate for a PR
# in another. The worktree cases below are the second one observed: the gate
# checking the session's directory instead of the worktree the PR came from.

set -uo pipefail

gate=${1:?usage: codex-review-gate-test.sh <path to codex-review-gate.sh>}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export XDG_STATE_HOME="$work/state"

# A stand-in for codex. The gate only needs to know whether the review ran to
# completion, which is its exit status.
fakebin="$work/bin"
mkdir -p "$fakebin"
printf '#!/bin/sh\nexit "${FAKE_CODEX_STATUS:-0}"\n' >"$fakebin/codex"
chmod +x "$fakebin/codex"

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

# Runs a review in a directory, the way codex-review-run does.
review() {
  local dir=$1
  shift
  (cd "$dir" && PATH="$fakebin:$PATH" bash "$gate" run "$@" >/dev/null 2>&1)
}

# Echoes the exit status so a blocked call does not abort the run. The command
# goes into the JSON literally, so \t and \n in it arrive as real characters.
check() {
  printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "${2:-gh pr create --fill}" |
    bash "$gate" check >/dev/null 2>&1
  echo $?
}

# Same, for commands carrying quotes or real newlines: jq builds the JSON.
check_cmd() {
  jq -nc --arg cwd "$1" --arg c "$2" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $c}}' |
    bash "$gate" check >/dev/null 2>&1
  echo $?
}

# Feeds stdin verbatim, for payloads that are not valid JSON at all.
check_raw() {
  printf '%s' "$1" | bash "$gate" check >/dev/null 2>&1
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

# The first reported hole.
review "$work/repo_a" --base main
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
expect "an empty cwd is refused" 2 "$(check "")"

# The record is written when a review ends. Asking for one is not a review: the
# earlier gate opened on the skill loading, before anything had been read.
mkrepo repo_c
FAKE_CODEX_STATUS=1 review "$work/repo_c" --base main
expect "a review that failed does not open the gate" 2 "$(check "$work/repo_c")"

review "$work/repo_c" --uncommitted
expect "a review of uncommitted changes does not open the gate" 2 "$(check "$work/repo_c")"

review "$work/repo_c" "look for bugs"
expect "a free-form review does not open the gate" 2 "$(check "$work/repo_c")"

old_c=$(git -C "$work/repo_c" rev-parse HEAD)
commit repo_c second
review "$work/repo_c" --commit "$old_c"
expect "a review of an older commit does not open the gate for HEAD" 2 "$(check "$work/repo_c")"

review "$work/repo_c" --commit HEAD
expect "a review of the HEAD commit opens the gate" 0 "$(check "$work/repo_c")"

# The second reported hole: the payload's cwd is the session's directory, and
# the PR comes from a worktree entered with cd.
git -C "$work/repo_b" worktree add -q -b feature "$work/repo_b_wt"
echo feature >>"$work/repo_b_wt/marker"
git -C "$work/repo_b_wt" add marker
git -C "$work/repo_b_wt" -c user.email=t@example -c user.name=t commit -q -m feature
review "$work/repo_b" --base main
expect "a review of the main checkout does not open a PR from the worktree" 2 \
  "$(check_cmd "$work/repo_b" "cd $work/repo_b_wt && gh pr create --fill")"

review "$work/repo_b_wt" --base main
expect "a review of the worktree opens a PR from the worktree" 0 \
  "$(check_cmd "$work/repo_b" "cd $work/repo_b_wt && gh pr create --fill")"
expect "a quoted cd path is still followed" 0 \
  "$(check_cmd "$work/repo_b" "cd \"$work/repo_b_wt\" && gh pr create --fill")"
expect "--head names the branch whose commit is checked" 0 \
  "$(check_cmd "$work/repo_b" "gh pr create --head feature --fill")"
expect "a cd the gate cannot resolve is refused" 2 \
  "$(check_cmd "$work/repo_b" 'cd "$WT" && gh pr create --fill')"

# Only the command itself counts. A prompt or a heredoc that mentions it is an
# argument to some other program — the third reported hole.
expect "the words inside a quoted argument are not the command" 0 \
  "$(check_cmd "$work/plain" 'codex exec "never run gh pr create yourself"')"
expect "the words inside a heredoc body are not the command" 0 \
  "$(check_cmd "$work/plain" "$(printf 'cat <<EOF >note.md\ngh pr create --fill\nEOF')")"
expect "the command after && is still seen" 2 "$(check_cmd "$work/plain" "git push && gh pr create --fill")"
expect "the command after ; is still seen" 2 "$(check_cmd "$work/plain" "git push; gh pr create --fill")"
expect 'the command inside $( ) is still seen' 2 "$(check_cmd "$work/plain" 'url=$(gh pr create --fill)')"
expect "an assignment in front does not hide the command" 2 "$(check_cmd "$work/plain" "GH_REPO=x/y gh pr create --fill")"

# The gate must stay out of the way of every other Bash command.
expect "an unrelated command is untouched" 0 "$(check "$work/repo_b" "git status")"

# Reformatting the command must not walk past the gate. Matching the spelling
# literally let every one of these through.
expect "two spaces between the words is still seen" 2 "$(check "$work/plain" "gh  pr  create --base main")"

# The JSON payload carries \t and \n through to the gate as real characters.
expect "a tab between the words is still seen" 2 "$(check "$work/plain" 'gh\tpr\tcreate')"
expect "a newline between the words is still seen" 2 "$(check "$work/plain" 'gh pr\ncreate --base main')"
expect "a continued line is still seen" 2 "$(check "$work/plain" 'gh pr \\\ncreate --base main')"

# A payload this hook cannot parse used to be a free pass: nothing was
# extracted, nothing matched, and the command went through with no marker
# anywhere. It is matched against its raw text now.
expect "an unparsable payload naming the command is refused" 2 \
  "$(check_raw "$(printf '{"cwd":"%s","tool_input":{"command":"gh\tpr\tcreate"}}' "$work/plain")")"

# Deliberately still allowed: refusing every payload that fails to parse would
# refuse every Bash command in the session, and one that never names the
# command was never going to open a PR.
expect "an unparsable payload naming nothing is allowed" 0 "$(check_raw "not json at all")"

# Nothing above proves the suite is watching the gate rather than agreeing with
# itself: every refusal would also pass against a gate that refuses everything.
# Remove the one thing that makes a refusal a refusal, and the refusals have to
# stop — otherwise these cases are not reading the gate.
broken="$work/broken-gate"
sed 's/exit 2/exit 0/' "$gate" >"$broken"
chmod +x "$broken"
printf '{"cwd":"%s","tool_input":{"command":"gh pr create"}}' "$work/plain" |
  bash "$broken" check >/dev/null 2>&1
expect "a gate with its refusal removed stops refusing" 0 "$?"

# And the other direction: a gate that opens everything would pass every "0"
# above. Make the marker check always succeed, and a refusal that depended on
# a missing review has to disappear.
lenient="$work/lenient-gate"
sed 's/\[ ! -f "\$marker_dir\/\$sha" \]/false/' "$gate" >"$lenient"
chmod +x "$lenient"
if cmp -s "$gate" "$lenient"; then
  expect "the lenient mutation was applied" changed unchanged
fi
got=$(
  printf '{"cwd":"%s","tool_input":{"command":"gh pr create"}}' "$work/repo_a" |
    bash "$lenient" check >/dev/null 2>&1
  echo $?
)
expect "a gate that ignores missing reviews stops refusing unreviewed commits" 0 "$got"

echo
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
