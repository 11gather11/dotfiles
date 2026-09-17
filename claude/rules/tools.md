# Preferred Tools

Use these tools instead of their standard alternatives:

| Tool             | Replaces | Description         |
| ---------------- | -------- | ------------------- |
| `fish`           | bash     | Environment shell   |
| `rg`             | grep     | Fast search         |
| `fd`             | find     | File finder         |
| `bat`            | cat      | Syntax highlighting |
| `eza`            | ls       | Git-aware listing   |
| `dust`           | du       | Disk usage          |
| `typos`          | -        | Spell checker       |
| `bunx` / `bun x` | npx      | Package runner      |
| `jq`             | -        | JSON processor      |
| `gh`             | git      | GitHub CLI          |

For code pattern searches (constructs, structure, not plain text), use the `ast-grep` skill rather than `rg`.

## Shell

Fish bootstraps the environment; it is not necessarily the syntax shell. Run simple commands as `fish -lc '<command>'` so PATH and exports are initialised. When a command needs bash/zsh syntax, nest it: `fish -lc 'bash -lc "<posix command>"'`.

## Reading Other Repositories

- A handful of known files: `gh repo read-file` / `gh repo read-dir` instead of cloning.
- A whole repo (searching, history, running builds): clone with `ghq` instead of `git clone` into `/tmp` or the current project. Treat the clone as read-only reference; never commit or push to it.

## Tips

- if you use `gh do` command, you can pass github credentials via environment variables. See `gh do --help` for more details.
