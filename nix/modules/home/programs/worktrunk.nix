# Git worktree manager. The agents here are told to create worktrees with `wt`
# rather than raw `git worktree` — see agents/shared/git-worktrees.md.
#
# docs
# https://worktrunk.dev/hook/
{ pkgs, lib, ... }:
let
  tomlFormat = pkgs.formats.toml { };

  # herdr's own worktree command opens a workspace for the checkout it makes,
  # but an agent working in a herdr pane creates its worktree with `wt`, which
  # herdr never hears about. The hooks below call this to give a `wt` worktree
  # the same life a herdr one has: a workspace appears when it is created and
  # goes when it is removed.
  #
  # Guarded on HERDR_ENV, which herdr sets in its panes and which wt passes
  # through to hooks; outside herdr there is no server to talk to.
  wt-herdr = pkgs.writeShellApplication {
    name = "wt-herdr";
    runtimeInputs = [
      pkgs.llm-agents.herdr
      pkgs.jq
      pkgs.git
    ];
    text = ''
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
in
{
  home.packages = [ pkgs.worktrunk ];

  xdg.configFile."worktrunk/config.toml".source = tomlFormat.generate "worktrunk-config.toml" {
    # wt warns on every `config show` while this is unset, because the default
    # is due to change to 2. Its suggested fix, `wt config update`, rewrites
    # this file, which is a read-only link into the store — so it is set here.
    list.json-schema = 2;

    # post-start fires once, on creation — not on switching to an existing
    # checkout. The workspace opens without focus, so the pane that ran `wt`
    # stays on screen; that is usually an agent still in the middle of its work.
    post-start.herdr = "${wtHerdr} open {{ worktree_path }} {{ branch }} {{ primary_worktree_path }}";

    # post-remove, which runs in the background after the removal. An agent
    # often removes the worktree it is standing in, so this closes the very
    # workspace that ran `wt`; done from here, the worktree and branch were
    # still removed.
    post-remove.herdr = "${wtHerdr} close {{ worktree_path }}";
  };
}
