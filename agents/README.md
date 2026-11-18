# Agent Skills

Shared skills for AI agents (Claude Code, Codex, etc.) managed via [agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix).

## Shared Instructions (`shared/`)

`agents/shared/*.md` is the single source of truth for instruction sections used by multiple agents (Code Comments Policy, Command Privacy, Git Staging, Git Worktrees):

`agents/AGENTS.md` is the entry point every agent shares, and imports the fragments with `@~/.config/claude/shared/*.md`:

- **Claude Code**: reads `agents/AGENTS.md` as `~/.config/claude/CLAUDE.md`, a symlink, so edits apply without a switch (`nix/modules/home/programs/claude-code/default.nix`)
- **Codex**: `~/.codex/AGENTS.md` (`$CODEX_HOME`) is generated at switch time from `agents/AGENTS.md`, with the imports replaced by the fragments' text and `codex/AGENTS.md` (Codex-only sections) appended (`nix/modules/home/programs/codex.nix`)

Edit the fragments here, never the per-agent copies. Codex picks up changes only after `nix run .#switch`.

## Configuration

Skills are configured in `nix/modules/home/agent-skills.nix` and deployed to:

- `~/.config/claude/skills/`
- `~/.config/codex/skills/`

## Adding a New Skill

1. Create a directory with a `SKILL.md` file
2. Enable it in `agent-skills.nix`:
   ```nix
   skills.enable = [ "my-skill" ];
   ```
3. Run `git add <my-skill> ../nix/modules/home/agent-skills.nix && nix run .#switch`

## Skill Design Guidelines

### Dynamic Context with Command Substitution

Use `` !`command` `` syntax to inject dynamic context inline. Embed it naturally in text rather than creating separate sections.

**Example:**

```markdown
**Current branch:** `!\`git branch --show-current\``

**Version:**`!\`tool --version 2>/dev/null || echo "not installed"\``
```

**Dynamic:** current state, CLI help, environment info
**Static:** workflow steps, best practices, examples

Reference: https://code.claude.com/docs/en/skills#inject-dynamic-context
