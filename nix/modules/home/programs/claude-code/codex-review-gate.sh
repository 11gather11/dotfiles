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
#
# What this does not stop, so that the gate is not mistaken for more than it
# is. Each of these takes knowing the gate is there and going around it, which
# is a different thing from forgetting to review:
#
#   - opening the PR through the API instead, `gh api .../pulls -f title=x`.
#     Only the porcelain spelling is matched.
#   - splitting the command across lines with a trailing backslash, which puts
#     the words on separate lines where a line-oriented match cannot see them.
#   - invoking codex-review and then not reading it. `mark` runs when the Skill
#     tool returns, and the tool returns "Launching skill: ..." at load time,
#     not when a review has been carried out. Nothing here can tell those apart.
#
# So the gate makes skipping the review deliberate rather than impossible.
#
# In the other direction, one way of reviewing does not open it: typing
# `/codex-review` never reaches the Skill tool, so `mark` never runs and the
# gate stays shut. Ask for the skill rather than typing the command, or expect
# to be refused after a review that did happen.

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
  # Runs of whitespace rather than one literal space. A second space or a tab
  # between the words is what reformatting produces, and matching the spelling
  # exactly let that straight through.
  printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create' || exit 0

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
