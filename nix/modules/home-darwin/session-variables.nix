# home.sessionVariables reach the shells through hm-session-vars.sh, which an
# application started from the Dock or Finder never sources. Anything such an
# application starts inherits the launchd session's environment instead, so a
# variable declared for the shells was missing there: herdr-core, started by
# Herdr.app, ran `hc run -- claude` without CLAUDE_CONFIG_DIR and Claude Code
# came up logged out against an empty ~/.claude.
#
# This publishes every declared variable to the launchd session at login, so a
# module declaring one does not also have to know that GUI processes exist.
# Already running processes keep the environment they started with; an
# application picks a change up on its next start.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # launchd stores a value as given and never expands it, so one written in
  # terms of another variable ($TERMINFO_DIRS, prepended to itself) would arrive
  # as that literal text. Those stay shell-only.
  literal = lib.filterAttrs (_: v: !lib.hasInfix "$" (toString v)) config.home.sessionVariables;

  publish = pkgs.writeShellScript "publish-session-variables" (
    lib.concatStrings (
      lib.mapAttrsToList (
        name: value:
        "/bin/launchctl setenv ${lib.escapeShellArg name} ${lib.escapeShellArg (toString value)}\n"
      ) literal
    )
  );
in
{
  # home-manager reloads an agent whose plist changed, and the script's store
  # path is in the plist, so a changed variable is published by the switch that
  # changes it, not only at the next login.
  launchd.agents.session-variables = {
    enable = true;
    config = {
      ProgramArguments = [ "${publish}" ];
      RunAtLoad = true;
    };
  };
}
