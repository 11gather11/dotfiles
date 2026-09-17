## Command Privacy and Secret Handling

- Never put raw secrets (tokens, API keys, passwords, private keys, cookies, credential-bearing env values) in command text: not as inline assignments like `TOKEN=... command` or `NIX_CONFIG="access-tokens = github.com=..."`, curl headers, query parameters, heredocs, or config snippets. Command text lands in shell history, process lists, and agent transcripts.
- Read secrets at execution time from an existing credential helper or environment instead: `$(gh auth token)`, `$GITHUB_TOKEN`. Use placeholders such as `<token>` only in explanatory text.
- Do not echo, print, log, summarise, commit, or paste secret values. If one is exposed, tell the user to rotate or revoke it; deleting shell history is not sufficient.

## Execution Safety

- Exploration runs against fixtures, dry runs, or resources that can be thrown away — never
  production data, and never an operation that cannot be undone.
- An effect outside this machine — sending, publishing, deleting, paying, messaging someone —
  needs the user to have asked for it. Approval for one such action does not carry to the next.
