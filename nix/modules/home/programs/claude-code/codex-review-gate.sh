#!/usr/bin/env bash
# Keeps `gh pr create` behind the codex-review skill.
#
# `mark` records that a review happened; `check` refuses to open the gate
# without that record. Both read the hook payload as JSON on stdin.
#
# What is recorded is the HEAD commit of the tree that was reviewed, not the
# bare fact that some review ran somewhere. One marker shared by every project
# is opened by a review in any of them, so a review in one repository lets an
# unreviewed PR out of another — which is how a PR reached GitHub from here
# with no review of its own.
#
# Keying on HEAD also shuts the gate again once commits are added after the
# review: those commits are exactly the ones nobody has looked at.

set -uo pipefail

mode=${1:-}
input=$(cat)

marker_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-codex-review"

# `cwd` is a top-level field of the hook payload; it is not inside tool_input.
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')

# Empty output means no commit could be resolved — an empty checkout, or a cwd
# that is not a repository at all. Callers must treat that as "no review".
head_sha() {
  [ -n "$cwd" ] || return 0
  git -C "$cwd" rev-parse HEAD 2>/dev/null
}

case "$mode" in
mark)
  skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // .tool_input.skillName // ""')
  [ "$skill" = "codex-review" ] || exit 0

  sha=$(head_sha)
  [ -n "$sha" ] || exit 0

  mkdir -p "$marker_dir" || exit 0
  : >"$marker_dir/$sha"

  # A marker older than this belongs to a tree nobody is still opening a PR
  # for, and the directory otherwise grows one file per reviewed commit.
  find "$marker_dir" -type f -mtime +30 -delete 2>/dev/null || true
  ;;

check)
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
  printf '%s' "$cmd" | grep -q 'gh pr create' || exit 0

  sha=$(head_sha)
  if [ -n "$sha" ] && [ -f "$marker_dir/$sha" ]; then
    exit 0
  fi

  # Nothing is consumed on the way through: while HEAD stays put the review
  # still covers the tree, and a second PR off the same commit is as
  # reviewed as the first.
  echo 'BLOCKED: You must run the codex-review skill first before creating a PR. Use Skill(codex-review) to review changes against the base branch. The review must cover the current HEAD, so run it again if commits were added since.' >&2
  exit 2
  ;;
esac

exit 0
