# Codex Global Instructions

- Always communicate in Japanese

## Python Execution

When executing Python scripts, always use `uv` instead of `python` directly:

```bash
# Use uv to run Python scripts
uv run script.py

# Or for inline execution
uv run python -c "print('hello')"
```

This ensures consistent Python environment management without requiring global Python installations.

## Browser Automation

- In Codex Desktop, automatically use the installed Browser plugin (`@Browser`) for tasks that require opening, navigating, inspecting, testing, screenshotting, or verifying web pages, even when the user does not mention the plugin explicitly.
- Prefer the Browser plugin and the in-app browser over the standalone `agent-browser` skill whenever the Browser plugin is available.
- Use `agent-browser` only when the Browser plugin is unavailable or cannot handle the target, and briefly state the reason before falling back.
- Use Chrome instead when the task specifically requires an existing signed-in browser session, cookies, extensions, or the user's current Chrome tabs.

## Missing Tools

Use the `missing-tools` skill when a command is unavailable, a shell reports `command not found`, or a tool must be run without installing it globally.

## Social Media Posts & YouTube Transcripts

For X/Twitter, Bluesky, and YouTube, use the `web-fetch` skill. It provides the packaged `tgrab` executable for fetching supported URLs.

Always fetch via a subagent to keep the main conversation clean. See the `web-fetch` skill for supported URL patterns and options.
