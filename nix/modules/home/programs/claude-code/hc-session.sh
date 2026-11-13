# Records which conversation a herdr-core terminal holds, for claude-resume
# (herdr-app.nix) to start it again there after the core is stopped or the
# machine restarts: herdr-core keeps its terminals and their labels across
# both, but not the programs in them.
#
#   hc-session start   SessionStart: label the terminal with the session's id
#   hc-session end     SessionEnd: forget it when the person ended the session,
#                      and that the terminal held its repository's harness
#
# Reads the hook's JSON on stdin. Always exits 0: a hook that fails here would
# only put noise in front of the person, and the cost of a missed label is a
# conversation resumed by hand.

[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
command -v hc >/dev/null || exit 0
input=$(cat)
id=$(jq -r '.session_id // empty | select(test("^[A-Za-z0-9-]+$"))' <<<"$input")
[ -n "$id" ] || exit 0

case "${1:-}" in
start)
  # Only the Claude the terminal itself runs, not one a session starts under
  # it (`claude -p` from a Bash call or a script): that one would label the
  # terminal with a conversation nobody is looking at. Walk up from this hook
  # to the terminal's own process, counting the Claude processes on the way;
  # the terminal's own Claude is the only one there.
  term=$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null | jq -r '.pid // empty')
  [ -n "$term" ] || exit 0
  claudes=0
  pid=$$
  while [ "$pid" -gt 1 ]; do
    [ "$(ps -o comm= -p "$pid")" = claude ] && claudes=$((claudes + 1))
    [ "$pid" = "$term" ] && break
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
    [ -n "$pid" ] || exit 0
  done
  [ "$pid" = "$term" ] && [ "$claudes" -eq 1 ] || exit 0

  # claude.resumed is claude-resume's note that it already sent this id;
  # a session that started clears it, so a later loss is resumed again.
  hc label "$HC_TERMINAL_ID" "claude.session=$id" "claude.resumed=" >/dev/null 2>&1
  ;;
end)
  # Ended by the person (/exit, ctrl-d, logging out): nothing to come back
  # to. Any other end, a lost terminal or a stopped core among them, keeps
  # the label so the conversation is resumed.
  case "$(jq -r '.reason // empty' <<<"$input")" in
  prompt_input_exit | logout) ;;
  *) exit 0 ;;
  esac
  # Matched on the id rather than by walking up as at the start: Claude does
  # not wait for this hook, so its process may be gone already. The label
  # names the terminal's own session, so a session started under it never
  # matches.
  held=$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null | jq -r '.labels["claude.session"] // empty')
  [ "$held" = "$id" ] || exit 0
  # The harness label goes too: a Claude started there later is not one.
  hc label "$HC_TERMINAL_ID" "claude.session=" "claude.resumed=" "harness=" >/dev/null 2>&1
  ;;
esac
exit 0
