## Git Staging

- Stage explicit paths only: `git add <path> [<path> …]`
- Never use `git add -A`, `git add --all`, `git add .`, or `git add -u`. They
  sweep in every unrelated working-tree change, including files that are
  untracked on purpose — in a public repository, committing one is publishing
  it. `git commit -a`/`-am` bypasses the index the same way, so commit from the
  index only
- Run `git status --short` before staging, and build the path list from
  `git diff --name-only` plus the untracked files you actually created. A long
  path list is correct; a catch-all flag is not
- Staging for a build is not staging for a commit. A flake copies only tracked
  files into the store, so a **new** file has to be staged before
  `nix run .#switch` can see it — edits to already-tracked files do not. That
  staging is a build prerequisite, not a commit plan
- Before committing, re-read the index with `git diff --cached --stat` and
  unstage anything the task did not touch: `git restore --staged <path>`
