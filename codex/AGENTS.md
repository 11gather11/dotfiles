# Codex Global Instructions

- Always communicate in Japanese

## Code Comments Policy

- Do NOT add comments explaining what was changed or why a change was made
- Comments like `// changed from X to Y` or `// updated for feature Z` are forbidden
- Only add comments when the logic itself is genuinely complex and non-obvious
- If a change needs explanation, write it in the git commit message instead
- Git commits should contain detailed explanations of what changed and why

## Python Execution

When executing Python scripts, always use `uv` instead of `python` directly:

```bash
uv run script.py
uv run python -c "print('hello')"
```

## Available Tools

- **Search**: Use `rg` (ripgrep) instead of grep
- **Find**: Use `fd` instead of find
- **JSON**: Use `jq` for JSON processing
- **Shell**: Fish shell is the primary shell
- **Package runner**: Use `bunx` instead of npx

## Missing Tools

**Always use [comma](https://github.com/nix-community/comma) first** when a tool is not installed:

```bash
, <command>           # Run any command from nixpkgs without installing
```

**Priority order** for running unavailable tools:

1. `, <command>` (comma) - preferred, simplest
2. `nix run nixpkgs#<package>` - when you need a specific package name
3. `nix-shell -p <package> --run "<command>"` - last resort
