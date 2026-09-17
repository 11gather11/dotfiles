---
name: web-fetch
description: Fetches web content with the tool that works for the page — WebFetch, curl, tgrab, or a browser. Use when reading a URL, a social media post, or a video transcript.
---

# Web Fetch

## A page

Try in this order, moving on when one fails (403, timeout, aborted):

1. **WebFetch** — the default.
2. **curl** — for a 403 from WebFetch: `curl -sL -A "claude-code/1.0" <url>`. Most of those
   403s are Cloudflare rejecting the `Claude-User` User-Agent, and a different one gets through.
3. **agent-browser skill** — when the page needs JavaScript, a login, or interaction.
4. **Chrome MCP** (`mcp__claude-in-chrome__*`) — when the page needs the browser the user is
   already signed in to.

## A social media post or a video transcript

`tgrab` handles what the order above stalls on. **Reach for it before the browser tools**: it
answers in one call what steps 3 and 4 spend a session on.

```bash
tgrab https://x.com/<user>/status/<id>
tgrab -l ja https://youtu.be/<id>          # transcript language
```

It detects the service from the URL and prints the text. `tgrab --help` carries the full
contract — every supported URL pattern and option. It used to ship a skill of its own; upstream
dropped that in favour of the help text, so read the help rather than looking for a skill.

## Reading a lot

Fetching a page brings its whole text into this context. When the answer is small but the
reading is bulky — several pages, a long document, a search that needs following up — hand the
task to a subagent instead; `agents/shared/delegate-work.md` is the policy and the `ask-codex`
skill is one way to do it.

Fetch it here when the wording is what you came for — an exact option name, a version string, a
quote. A subagent returns a digest, and a digest rewrites the names.
