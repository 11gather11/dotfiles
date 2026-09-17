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

## Available Tools

The following tools are preferred and available globally:

- **Search**: Use `rg` (ripgrep) instead of grep
- **Find**: Use `fd` instead of find
- **JSON**: Use `jq` for JSON processing
- **Shell**: Fish — it builds the environment; see the Shell section below

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

## Tips

- if you use `gh do` command, you can pass github credentials via environment variables. See `gh do --help` for more details.

## Shell

- Fish bootstraps the environment; it is not necessarily the syntax shell. Run simple commands as `fish -lc '<command>'` so PATH and exports are initialised.
- If a command uses Bash-specific syntax, fragile quoting, heredocs, arrays, inline environment assignments, or command substitutions, nest it rather than asking Fish to parse it: `fish -lc 'bash -lc "<posix command>"'`.
- For complex multi-line commands, prefer an existing script, or create one with the right shebang and invoke it with the appropriate interpreter.
