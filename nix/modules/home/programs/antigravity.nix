{
  pkgs,
  lib,
  config,
  helpers,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  agySettings = "${config.home.homeDirectory}/.gemini/antigravity-cli/settings.json";

  # Only the keys this file owns, in the form agy's own /config writes them.
  # Everything else in settings.json — the trusted workspaces, anything set
  # from /config later — is left as agy wrote it.
  settings = {
    # agy's terminal sandbox cannot run anything here. Its Seatbelt profile
    # denies everything and then allows reads and execs under a built-in list —
    # /Applications, /opt/homebrew, the system paths — with no setting to add
    # to it, and every shell and tool on this machine lives in /nix/store. The
    # shell itself fails to start, so under proceed-in-sandbox every command
    # fell through to an approval prompt.
    enableTerminalSandbox = false;

    # So commands ask, as Claude Code does for what its classifier stops, and
    # the ones that only read go through unasked. A rule matches a command line
    # by prefix and never a chained one: `git status && ...` still asks.
    toolPermission = "request-review";
    # The list is owned whole: rules added from agy's own prompts are replaced
    # at the next switch, so a rule worth keeping belongs here.
    permissions.allow = map (command: "command(${command})") [
      "rg"
      "fd"
      "ls"
      "eza"
      "bat"
      "cat"
      "head"
      "tail"
      "wc"
      "jq"
      "git status"
      "git diff"
      "git log"
      "git show"
      "git blame"
      # herdr's reads only, which the herdr skill starts with; creating,
      # closing and prompting panes still ask.
      "herdr pane list"
      "herdr pane read"
      "herdr pane layout"
      "herdr tab list"
      "herdr workspace list"
      "herdr agent list"
      "herdr agent get"
      "herdr agent read"
    ];
  };

  # settings.json cannot be generated whole: agy records the workspaces it has
  # been trusted in into the same file, and overwriting it would ask again in
  # every one after each switch.
  mergeConfig = helpers.mergeConfig pkgs;
in
{
  # Google's Antigravity agent in the terminal, as `agy`. From llm-agents
  # rather than nixpkgs, which carries the same CLI several releases behind.
  home.packages = [ pkgs.llm-agents.antigravity-cli ];

  home.activation.writeAgySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${mergeConfig} ${lib.escapeShellArg agySettings} ${jsonFormat.generate "agy-settings.json" settings}
  '';
}
