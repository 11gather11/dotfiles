## Git Commit Signing

Commits are signed by default with a key in 1Password's agent, so each
signature waits for Touch ID. Repositories agents commit to sign with the
passphrase-less `~/.ssh/ai_signing` instead, chosen per repository by the
untracked `~/.gitconfig.ai-signing`. The same file sends their GitHub traffic
over HTTPS whatever the remote URL says, since SSH authentication also goes
through 1Password. The setup is explained in
`~/ghq/github.com/11gather11/dotfiles/nix/modules/home/programs/git/default.nix`.

- When signing hangs or fails, run `git config --show-origin user.signingkey`
  to see which key was chosen and where from, before changing anything
- Never set `commit.gpgsign` or `user.signingkey` in a repository's
  `.git/config` to get past it. That is the scattered per-repository setup this
  replaced, and an unsigned commit is not an acceptable result
- If the repository is not in `~/.gitconfig.ai-signing`, stop and ask the user
  whether to add it; which repositories an agent may sign for is their call
