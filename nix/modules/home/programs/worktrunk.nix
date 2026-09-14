# Git worktree manager. The agents here are told to create worktrees with `wt`
# rather than raw `git worktree` — see agents/shared/git-worktrees.md.
#
# docs
# https://worktrunk.dev/hook/
{ pkgs, lib, ... }:
let
  tomlFormat = pkgs.formats.toml { };

  herdr = lib.getExe pkgs.llm-agents.herdr;
  jq = lib.getExe pkgs.jq;
in
{
  home.packages = [ pkgs.worktrunk ];

  xdg.configFile."worktrunk/config.toml".source = tomlFormat.generate "worktrunk-config.toml" {
    # wt warns on every `config show` while this is unset, because the default
    # is due to change to 2. Its suggested fix, `wt config update`, rewrites
    # this file, which is a read-only link into the store — so it is set here.
    list.json-schema = 2;

    # herdr's own worktree command opens a workspace for the checkout it makes,
    # but an agent working in a herdr pane creates its worktree with `wt`, which
    # herdr never hears about. These hooks give a `wt` worktree the same life a
    # herdr one has: a workspace appears when it is created and goes when it is
    # removed.
    #
    # Both are guarded on HERDR_ENV, which herdr sets in its panes and which wt
    # passes through to hooks; outside herdr there is no server to talk to.

    # post-start fires once, on creation — not on switching to an existing
    # checkout. --no-focus keeps the pane that ran `wt` on screen, since that is
    # usually an agent still in the middle of its work.
    post-start.herdr = ''
      [ -n "$HERDR_ENV" ] && ${herdr} worktree open --cwd {{ primary_worktree_path }} --path {{ worktree_path }} --label {{ branch }} --no-focus >/dev/null
    '';

    # post-remove, which runs in the background after the removal. An agent
    # often removes the worktree it is standing in, so this closes the very
    # workspace that ran `wt`; done from here, the worktree and branch were
    # still removed.
    post-remove.herdr = ''
      [ -n "$HERDR_ENV" ] && ${herdr} workspace list | ${jq} -r --arg p {{ worktree_path }} '.result.workspaces[] | select(.worktree.checkout_path == $p) | .workspace_id' | xargs -n1 ${herdr} workspace close
    '';
  };
}
