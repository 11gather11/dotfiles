# Git worktree manager. The agents here are told to create worktrees with `wt`
# rather than raw `git worktree` — see agents/shared/git-worktrees.md.
#
# docs
# https://worktrunk.dev/hook/
{
  pkgs,
  lib,
  config,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };

  # herdr's own worktree command opens a workspace for the checkout it makes,
  # but an agent working in a herdr pane creates its worktree with `wt`, which
  # herdr never hears about. The hooks below call this to give a `wt` worktree
  # the same life a herdr one has: a workspace appears when it is created and
  # goes when it is removed.
  #
  # herdr-app is the same story: it shows a worktree as a space nested under
  # its repository's, but only once a space exists for it, and wt never tells
  # it. So in a herdr-app terminal (herdr-core sets HC_TERMINAL_ID) the hooks
  # open and close a space there instead; in a herdr pane (HERDR_ENV) they
  # talk to herdr as before. Outside both there is no server to talk to.
  #
  # herdr-app is not on runtimeInputs: the app installs its own CLI into
  # ~/.local/bin, which is on PATH, and no package here provides it.
  wt-herdr = pkgs.writeShellApplication {
    name = "wt-herdr";
    runtimeInputs = [
      pkgs.llm-agents.herdr
      pkgs.jq
      pkgs.git
    ];
    text = ''
      if [ -n "''${HC_TERMINAL_ID:-}" ]; then
        command -v herdr-app >/dev/null || exit 0
        case "$1" in
          open)
            # issue-harness opens a worker's space itself, with Claude as its
            # only terminal; a space opened here would add a shell beside it.
            if [ -n "''${HARNESS_WORKER:-}" ]; then
              exit 0
            fi
            path="$2"
            branch="$3"
            # space.new selects the space it makes; the worktree should appear
            # without taking the screen from whoever ran `wt`, as herdr's
            # --no-focus does, so the space shown before is selected again.
            shown="$(herdr-app ls | jq -r 'first(.spaces[] | select(.active) | .id) // empty')"
            herdr-app "do" space.new --folder "$path" --name "$branch" >/dev/null
            if [ -n "$shown" ]; then
              herdr-app "do" space.select --id "$shown" >/dev/null
            fi
            ;;
          close)
            path="$2"
            # A space's folder is where its first terminal is now, which may be
            # below the checkout's root.
            herdr-app ls \
              | jq -r --arg p "$path" '.spaces[] | select(.folder == $p or (.folder | startswith($p + "/"))) | .id' \
              | while read -r id; do herdr-app "do" space.close --id "$id" --confirmed true >/dev/null; done
            ;;
        esac
        exit 0
      fi

      [ -n "''${HERDR_ENV:-}" ] || exit 0

      case "$1" in
        open)
          path="$2"
          branch="$3"
          primary="$4"

          open_from() {
            herdr worktree open "$@" --path "$path" --label "$branch" --no-focus >/dev/null 2>&1
          }

          # The new workspace is grouped under a parent, and the parent should
          # be the workspace the agent ran `wt` from. Resolving it from the
          # repository path instead picks the first workspace with a pane
          # standing in that repository, which put a worktree under an
          # unrelated project whose first pane happened to be there.
          if [ -n "''${HERDR_WORKSPACE_ID:-}" ] && open_from --workspace "$HERDR_WORKSPACE_ID"; then
            exit 0
          fi

          # That is refused when `wt` ran from a worktree's own workspace
          # (herdr groups worktrees one level deep) or from a workspace that
          # belongs to another repository. Either way, the parent is whichever
          # workspace herdr already records as this repository's primary.
          repo_key="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir)"
          parent="$(herdr workspace list | jq -r --arg k "$repo_key" \
            'first(.result.workspaces[] | select(.worktree.repo_key == $k and (.worktree.is_linked_worktree | not)) | .workspace_id) // empty')"
          if [ -n "$parent" ] && open_from --workspace "$parent"; then
            exit 0
          fi

          # No workspace is recorded as the primary yet, so herdr's own
          # resolution by path is the only option left.
          open_from --cwd "$primary"
          ;;

        close)
          path="$2"
          herdr workspace list \
            | jq -r --arg p "$path" '.result.workspaces[] | select(.worktree.checkout_path == $p) | .workspace_id' \
            | while read -r id; do herdr workspace close "$id" >/dev/null; done
          ;;
      esac
    '';
  };
  wtHerdr = lib.getExe wt-herdr;

  # direnv records trust per path and content, so a new worktree's .envrc is
  # blocked even when it is byte for byte the one already allowed in the
  # primary checkout, and every shell opened there starts with an error. Trust
  # is carried over only in exactly that case: direnv judges an .envrc by its
  # content alone, so allowing the same content at another path trusts nothing
  # new. An .envrc the branch has changed still needs `direnv allow` by hand.
  wt-direnv = pkgs.writeShellApplication {
    name = "wt-direnv";
    runtimeInputs = [
      config.programs.direnv.package
      pkgs.jq
      pkgs.diffutils
    ];
    text = ''
      worktree="$1"
      primary="$2"

      [ -f "$worktree/.envrc" ] && [ -f "$primary/.envrc" ] || exit 0
      cmp -s "$worktree/.envrc" "$primary/.envrc" || exit 0

      # foundRC.allowed is 0 for allowed, 1 for not yet allowed, 2 for denied.
      allowed="$(cd "$primary" && direnv status --json | jq '.state.foundRC.allowed')" || exit 0
      [ "$allowed" = 0 ] || exit 0

      # This runs as a pre- hook, where a failure would abort creating the
      # worktree; a worktree whose .envrc stays blocked is still worth having.
      direnv allow "$worktree" || true
    '';
  };

  # Files kept out of git live only in the primary checkout, yet an agent
  # started in a new worktree needs them from its first turn: CLAUDE.local.md
  # carries the repository's local rules, and .claude/settings.local.json the
  # permission rules that make it ask before pushing. Each is linked back to
  # the primary's copy, and only when git ignores that path in the worktree:
  # a link at a path git does not ignore would be staged with the next commit.
  wt-local-files = pkgs.writeShellApplication {
    name = "wt-local-files";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      worktree="$1"
      primary="$2"
      [ "$worktree" != "$primary" ] || exit 0

      link() {
        local rel="$1"
        [ -e "$primary/$rel" ] || return 0
        # -L as well: a dangling link is still something not to overwrite
        [ -e "$worktree/$rel" ] || [ -L "$worktree/$rel" ] && return 0
        git -C "$worktree" check-ignore -q "$rel" || return 0
        mkdir -p "$(dirname "$worktree/$rel")"
        ln -s "$primary/$rel" "$worktree/$rel"
      }

      # This runs as a pre- hook, where a failure would abort creating the
      # worktree; a worktree without these files is still worth having.
      for rel in CLAUDE.local.md .claude/settings.local.json; do
        link "$rel" || true
      done
    '';
  };
  # A dev server an agent starts with `&` leaves its process group the moment
  # the command returns, so nothing tracks it: not the agent, not the pane, and
  # not `wt remove`. Two were found still holding 4GB days after their worktrees
  # were gone. Removing a worktree is the one moment that certainly marks its
  # processes as finished, whoever started them.
  #
  # Only processes without a terminal are stopped. One with a terminal is a
  # shell, editor or agent in a pane, and post-remove's herdr close ends those
  # along with the pane. The ancestors of this hook are spared too: that is the
  # shell and agent running `wt remove`, often from inside this worktree.
  wt-reap = pkgs.writeShellApplication {
    name = "wt-reap";
    runtimeInputs = [
      pkgs.lsof
      pkgs.gawk
      pkgs.coreutils
    ];
    text = ''
      worktree="$(realpath "$1")"

      spared=" "
      pid=$$
      while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
        spared+="$pid "
        pid="$(ps -o ppid= -p "$pid" | tr -d ' ')" || break
      done

      # lsof -F prints one field per line: "p<pid>" opens a process and the
      # "n<path>" after it is that process's working directory.
      targets=()
      while read -r pid; do
        [[ $spared == *" $pid "* ]] && continue
        tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')" || continue
        [ "$tty" = "??" ] || [ "$tty" = "?" ] || continue
        targets+=("$pid")
      done < <(
        lsof -a -d cwd -Fpn 2>/dev/null \
          | awk -v wt="$worktree" '
              /^p/ { pid = substr($0, 2) }
              /^n/ { p = substr($0, 2); if (p == wt || index(p, wt "/") == 1) print pid }
            '
      )

      [ ''${#targets[@]} -gt 0 ] || exit 0
      echo "wt-reap: stopping ''${targets[*]} in $worktree" >&2
      kill -TERM "''${targets[@]}" 2>/dev/null || true

      # workerd ignores SIGTERM, so whatever is still up after a grace period
      # is killed outright.
      for _ in 1 2 3 4 5; do
        alive=()
        for pid in "''${targets[@]}"; do
          kill -0 "$pid" 2>/dev/null && alive+=("$pid")
        done
        [ ''${#alive[@]} -gt 0 ] || exit 0
        sleep 1
      done
      kill -KILL "''${alive[@]}" 2>/dev/null || true
    '';
  };
in
{
  home.packages = [ pkgs.worktrunk ];

  xdg.configFile."worktrunk/config.toml".source = tomlFormat.generate "worktrunk-config.toml" {
    # wt warns on every `config show` while this is unset, because the default
    # is due to change to 2. Its suggested fix, `wt config update`, rewrites
    # this file, which is a read-only link into the store — so it is set here.
    list.json-schema = 2;

    # pre-start, which blocks until it finishes, so the .envrc is trusted
    # before post-start opens a herdr workspace and its shell loads direnv.
    pre-start.direnv = "${lib.getExe wt-direnv} {{ worktree_path }} {{ primary_worktree_path }}";

    # pre-start too: post-start opens the herdr workspace an agent starts in,
    # and the agent reads its local rules and permissions at launch.
    pre-start.local-files = "${lib.getExe wt-local-files} {{ worktree_path }} {{ primary_worktree_path }}";

    # post-start fires once, on creation — not on switching to an existing
    # checkout. The workspace opens without focus, so the pane that ran `wt`
    # stays on screen; that is usually an agent still in the middle of its work.
    post-start.herdr = "${wtHerdr} open {{ worktree_path }} {{ branch }} {{ primary_worktree_path }}";

    # pre-remove, so the processes are gone before their directory is.
    pre-remove.reap = "${lib.getExe wt-reap} {{ worktree_path }}";

    # post-remove, which runs in the background after the removal. An agent
    # often removes the worktree it is standing in, so this closes the very
    # workspace that ran `wt`; done from here, the worktree and branch were
    # still removed.
    post-remove.herdr = "${wtHerdr} close {{ worktree_path }}";
  };
}
