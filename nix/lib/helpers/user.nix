# Who the commits and the GitHub credential belong to.
#
# Not `config.home.username`, which this derived from until the Linux machine
# stopped sharing a name with the macOS one: Linux refuses an account starting
# with a digit, so there it is `gather`. The identity is the GitHub handle
# either way — the noreply address only works spelled exactly as the account
# is, and `gh auth token --user` looks the handle up, not the local login.
_: rec {
  username = "11gather11";
  githubId = "160300516";
  email = "${githubId}+${username}@users.noreply.github.com";
}
