function gh-q --description 'pick a GitHub account, then one of its repositories, and clone it into that account'"'"'s root'
    # The account is the only thing chosen here. It decides both which
    # repositories are listed and which root they are cloned into, because those
    # are the same fact: a repository belonging to the work account belongs in
    # the work root, where the work identity applies. Choosing them separately
    # is what let work repositories land under ~/ghq and take the personal name
    # and email.
    set -l account (
        command gh auth status --json hosts \
            --jq '.hosts["github.com"][] | .login' \
        | fzf --height 20% --reverse --prompt 'account> '
    )
    test -n "$account"; or return 0

    set -l root ~/ghq
    test "$account" = "$GH_WORK_ACCOUNT"; and set root ~/ghq-work

    # Name the token rather than inheriting one. gh uses whichever account is
    # active, and the active account here is the work one, so a listing without
    # this returns work repositories whichever account was picked. `command gh`
    # for the same reason: the gh function sets GH_TOKEN from the current
    # directory, which is not what decides things here.
    set -lx GH_TOKEN (command gh auth token --user $account)

    set -l query (string trim "
query (\$owner: String!, \$endCursor: String) {
  repositoryOwner(login: \$owner) {
    repositories(
      first: 30
      after: \$endCursor
    ){
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        nameWithOwner
      }
    }
  }
} ")

    set -l repo (
        command gh api graphql \
            --paginate \
            --field owner=$account \
            -f query="$query" \
            --jq '.data.repositoryOwner.repositories.nodes[].nameWithOwner' \
        | fzf --height 40% --reverse --prompt "$account> "
    )
    test -n "$repo"; or return 0

    # $root rather than a tilde inside the assignment: fish expands a tilde only
    # at the start of a word, so GHQ_ROOT=~/… would pass the literal string.
    env GHQ_ROOT=$root ghq get $repo; or return 1
    cd -- $root/github.com/$repo
end
