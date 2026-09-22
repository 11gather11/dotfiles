# PostToolUse hook: read the file a write just produced and, when it holds
# Japanese prose, hand suiko's findings back to the agent that wrote it.
#
# Most of the Japanese written here is written by an agent — ADRs, design notes,
# the instruction files in this repository — and its tells are consistent:
# bold-label bullets, a predicate followed by a colon, sentences of one length,
# `修正を行う` where `修正する` would do. suiko names them at a line and column.
# The point of catching it here rather than in a pre-commit hook is that the
# agent is still holding the context it wrote them in.
#
# Exit 2 is how a PostToolUse hook speaks to the agent: stderr comes back as
# something to act on. The write has already happened, so this is a remark
# rather than a veto — nothing is reverted, and a finding that reads as noise
# can be left alone.

input=$(cat)

file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[[ -n $file ]] || exit 0
[[ -f $file ]] || exit 0

case $file in
*.md | *.markdown | *.txt) ;;
*) exit 0 ;;
esac

# Hiragana or katakana in the first part of the file. suiko is for Japanese
# prose; an English document scores badly on rules that do not apply to it.
head -c 20000 -- "$file" | grep -qP '[\x{3040}-\x{30ff}]' || exit 0

# `tech` holds the thresholds calibrated for technical writing, which is what
# this configuration and the repositories beside it contain. --fail-on warn
# keeps the informational findings out of the agent's way: the bold-label
# bullet is a house style in several ADRs here, while a forbidden phrase —
# `深掘りする` and its relatives — is the kind that reads as machine-written.
findings=$(suiko lint --genre tech --fail-on warn -- "$file" 2>&1) || {
  printf 'suiko が %s の日本語に指摘を出した。直すか、意図した文体として残すかを判断する。\n\n%s\n' \
    "$file" "$findings" >&2
  exit 2
}

exit 0
