# Web Fetch Strategy

When fetching web content, try methods in this order. Move to the next if the current one fails (e.g. 403, timeout, aborted):

1. **WebFetch tool** - Default. Try this first.
2. **curl fallback** - If WebFetch returns 403, retry with `curl -sL -A "claude-code/1.0" <url>`. Many 403s are caused by Cloudflare blocking the default `Claude-User` User-Agent.
3. **agent-browser skill** - Use `/agent-browser` skill for browser-based fetching.
4. **Chrome MCP** - Use `mcp__claude-in-chrome__*` tools to navigate and read the page.

## Social Media Posts & YouTube Transcripts (tgrab)

These need a browser or a login, so the fetch order above stalls on them. Run
`tgrab <url>` instead — it detects the service from the URL and prints the text.

Reach for it before the browser tools, not after: it answers in one call what
step 3 or 4 spends a session on.

    tgrab https://x.com/<user>/status/<id>
    tgrab -l ja https://youtu.be/<id>          # transcript language

`tgrab --help` carries the full contract — every supported URL pattern and
option. It used to ship an agent skill; upstream dropped that in favour of the
help text, so read the help rather than looking for a skill.
