abbr -a caf caffeinate -d

# editor
alias vim nvim
abbr -a v nvim
abbr -a nv nvim
abbr -a bash 'bash --norc'

# ls (eza)
alias ls eza
abbr ll 'ls -hl'
abbr la 'ls -hlA'
abbr lt 'ls --tree'
abbr lg 'ls -hlFg'

# navigation
abbr -a cdr 'cd -- (git root)'
abbr -a cdf __fzf_cd

# common shortcuts
abbr -a sc "source $FISH_CONFIG"
abbr -a src source
abbr -a br brew
abbr -a bri 'brew install'
abbr -a clr clear
abbr -a rr 'rm -r'
abbr -a rf 'rm -rf'
abbr -a mkd 'mkdir -p'
abbr -a mkdir 'mkdir -p'
abbr -a o open
abbr -a lzg lazygit
abbr -a lzd lazydocker
abbr -a vc 'code (pwd)'
abbr -a py python
abbr -a pbc pbcopy
abbr -a pbp pbpaste

# bun
abbr -a bunb 'bun --bun'
abbr -a bunbx 'bunx --bun'

# docker
abbr -a do docker container
abbr -a dop "docker container ps"
abbr -a dob "docker container build"
abbr -a dor "docker container run --rm"
abbr -a dox "docker container exec -it"

# docker compose
abbr -a dc docker compose
abbr -a dcu "docker compose up"
abbr -a dcub "docker compose up --build"
abbr -a dcd "docker compose down"
abbr -a dcr "docker compose restart"

# nix
abbr -a ns nix-shell
abbr -a ngc nix-collect-garbage
abbr -a nrn --set-cursor nix run nixpkgs#\%
abbr -a dv devenv

# git
abbr -a g git
abbr -a ga 'git add'
abbr -a ga. 'git add .'
abbr -a gaa 'git add --all'
abbr -a gco 'git checkout'
abbr -a gc 'git commit'
abbr -a gcn 'git commit -n'
abbr -a gcl 'git clone'
abbr -a --set-cursor gcm git commit -m \"%\"
abbr -a --set-cursor gcnm git commit -n -m \"%\"
abbr -a --set-cursor gcam git commit --amend -m \"%\"
abbr -a --set-cursor gcem git commit --allow-empty -m \"%\"
abbr -a gp 'git push'
abbr -a gpo 'git push origin'
abbr -a gpf git push --force-with-lease
abbr -a gpff git push --force
abbr -a gpl 'git pull'
abbr -a gf 'git fetch'
abbr -a gsw 'git switch'
abbr -a --set-cursor gswf 'git switch feature/%'
abbr -a gsm "command git switch main 2>/dev/null || command git switch master"
abbr -a gpt 'git push --tags'
abbr -a gr 'git rebase'
abbr -a gwt 'git wt'

# git abbreviations using --command option (fish 4.0+)
abbr -a -c git a add
abbr -a -c git aa add -a
abbr -a -c git ap add -p
abbr -a -c git cm commit -m
abbr -a -c git cma commit --amend -m
abbr -a -c git b branch
abbr -a -c git bm branch -m
abbr -a -c git bu rev-parse --abbrev-ref --symbolic-full-name @{u}
abbr -a -c git bv branch -vv
abbr -a -c git br browse
abbr -a -c git cl clone
abbr -a -c git cp cherry-pick
abbr -a -c git cpn cherry-pick -n
abbr -a -c git f fetch
abbr -a -c git p push
abbr -a -c git pf push --force-with-lease --force-if-includes
abbr -a -c git pushf push --force-with-lease --force-if-includes
abbr -a -c git rbm rebase origin/main
abbr -a -c git rst reset
abbr -a -c git rs restore
abbr -a -c git st stash
abbr -a -c git sts status -s -uno
abbr -a -c git sm submodule
abbr -a -c git smu submodule update --remote --init --recursive
abbr -a -c git sma submodule add
abbr -a -c git sw switch
abbr -a -c git swc switch -c
abbr -a -c git po push origin
abbr -a -c git difff diff --word-diff
abbr -a -c git cid log -n 1 --format=%H
abbr -a -c git clb clean-local-branches
abbr -a -c git id show -s --format=%H
abbr -a -c git co checkout
abbr -a -c git cob checkout -b
abbr -a -c git sha rev-parse HEAD
abbr -a -c git pl pull
abbr -a -c git wtd wt -D
abbr -a -c git pbr browse-pr

# gh
abbr -a ghp 'gh poi'
abbr -a -c gh pco 'pr checkout'
abbr -a -c gh pcr 'pr create'
abbr -a gh-fork-sync "gh repo list --limit 200 --fork --json nameWithOwner --jq '.[].nameWithOwner' | xargs -n1 gh repo sync"

# ghq
abbr -a gg 'ghq get'

# ai
abbr -a cl claude
abbr -a clc claude --continue
abbr -a clh claude --dangerously-skip-permissions --model haiku
abbr -a clo claude --model opus
abbr -a cls claude --model sonnet
abbr -a cls1 claude --model sonnet[1m]
abbr -a oc opencode
abbr -a cx codex
abbr -a ca cursor-agent
