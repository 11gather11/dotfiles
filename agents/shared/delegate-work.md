## Delegating Work

Work whose output is bulky but whose conclusion is small — web search, page
reading, codebase investigation, summarising long output, drafting a commit
message from a diff — belongs in your own native subagent (the Agent tool in
Claude Code, a native subagent in Codex), not in this context. Never start a
nested CLI of the agent you are running in. The `ask-codex` skill is for an
independent opinion from the other vendor, not a route for bulky reading.

What stays here: anything that needs this conversation's own history, and every
edit to the repo.

Claude Code's permission checker rejects compound commands (`cd … && … | …`)
from a subagent in an isolated worktree, because it cannot prove they stay
inside it. Brief such a subagent to run one simple command per call and to use
`git -C`.
