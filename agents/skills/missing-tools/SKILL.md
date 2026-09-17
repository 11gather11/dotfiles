---
name: missing-tools
description: Resolves missing CLI tools. Use when a command is unavailable, a shell reports command not found, or a tool must be run without installing it globally.
---

Use this workflow when a required command is unavailable:

1. Try the project environment: `direnv exec . <command>` — a project-local dev shell usually already has the right version and the environment variables that go with it.
2. Try comma: `, <command>`.
3. Use `nix run nixpkgs#<package> -- <args>` when a package is known.
4. Use `nix shell nixpkgs#<package> --command <command>` when a package is known but a temporary shell is required.

Exceptions:

- Script with a missing interpreter: read its shebang and run it with `nix shell nixpkgs#<package> --command ./<script>`.
- Last resort: `docker run --rm -v "$PWD:/workspace" -w /workspace <image> <command>`.

For GitHub-backed Nix fetches, use the `nix-github-rate-limit` skill.

Never install tools globally: not `npm install -g`, `npm i -g`, `pnpm add -g`, `yarn global add`, `bun add -g`, `uv tool install`, `brew install`, or any language-specific global installer.

Fish is the interactive shell here, so a tool may only be on Fish's PATH. If another shell cannot find a command, resolve its absolute path with `fish -lc 'command -v <tool>'` and invoke that path.
