# Review-first diff viewer, for reading what an agent changed. It took the job
# reviewr had and the one yazi's preview briefly grew: this is where a diff gets
# read here, and delta stays the pager for `git diff` and lazygit.
{ pkgs, helpers, ... }:
let
  tomlFormat = pkgs.formats.toml { };
in
{
  home.packages = [ pkgs.hunk ];

  xdg.configFile."hunk/config.toml".source = tomlFormat.generate "hunk-config.toml" {
    theme = helpers.theme.hunk;

    # The changesets read here are being written while they are read, in a pane
    # next to this one. Without this the view is of whatever the agent had
    # finished when the session opened.
    watch = true;

    # The notes an agent leaves beside the lines it changed are the reason for
    # choosing this viewer; hiding them behind a key makes it a diff viewer
    # with extra steps.
    agent_notes = true;

    # hunk offers to save changed view preferences on quit, and saves them by
    # rewriting this file — which is a read-only link into the store, so the
    # save fails. The settings live here instead; the prompt has nothing to
    # offer and is turned off rather than left to fail.
    prompt_save_view_preferences = false;
  };
}
