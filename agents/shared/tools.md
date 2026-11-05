# Preferred Tools

Use these tools instead of their standard alternatives:

| Tool             | Replaces | Description         |
| ---------------- | -------- | ------------------- |
| `rg`             | grep     | Fast search         |
| `fd`             | find     | File finder         |
| `bat`            | cat      | Syntax highlighting |
| `eza`            | ls       | Git-aware listing   |
| `dust`           | du       | Disk usage          |
| `typos`          | -        | Spell checker       |
| `bunx` / `bun x` | npx      | Package runner      |
| `uv run`         | python   | Python runner       |
| `jq`             | -        | JSON processor      |
| `gh`             | -        | GitHub operations   |

For code pattern searches (constructs, structure, not plain text), use the `ast-grep` skill rather than `rg`.

## Shell

Fish bootstraps the environment; it is not necessarily the syntax shell.

- Claude Code: run commands directly. Its zsh already has the Nix PATH, and `zsh/zshenv` loads direnv. Use `fish -lc '<command>'` only when a tool is on Fish's PATH but not found here.
- Codex: use `zsh -lc '<command>'`, which loads direnv. If a tool is only on Fish's PATH, resolve it with `fish -lc 'command -v <tool>'` and call the absolute path.
- Commands already start in the working directory, so don't add a redundant `cd <path> &&`. For another directory, use the harness's working-directory parameter where it has one, or the command's own option (`git -C`, `nix --flake`, `pnpm -C`).
- For complex multi-line commands, prefer an existing script, or create one with the right shebang and invoke it with the appropriate interpreter.

## Reading Other Repositories

- A handful of known files: `gh repo read-file` / `gh repo read-dir` instead of cloning.
- A whole repo (searching, history, running builds): clone with `ghq` instead of `git clone` into `/tmp` or the current project. Treat the clone as read-only reference; never commit or push to it.

## Tips

- if you use `gh do` command, you can pass github credentials via environment variables. See `gh do --help` for more details.
