# docs
# https://cmux.com/docs/configuration

{ pkgs, ... }:
let
  jsonFormat = pkgs.formats.json { };

  cmuxSettings = {
    "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
    schemaVersion = 1;

    app = {
      appearance = "dark";
      warnBeforeQuit = true;
      minimalMode = false;
    };

    automation = {
      claudeCodeIntegration = true;
      socketControlMode = "full";
    };

    notifications = {
      dockBadge = true;
      showInMenuBar = true;
      unreadPaneRing = true;
      paneFlash = true;
    };

    sidebar = {
      showPorts = true;
      showPullRequests = true;
      showProgress = true;
      showLog = true;
      showBranchDirectory = true;
      showSSH = true;
      branchLayout = "inline";
      openPullRequestLinksInCmuxBrowser = true;
      openPortLinksInCmuxBrowser = true;
    };

    sidebarAppearance = {
      matchTerminalBackground = true;
    };

    workspaceColors = {
      indicatorStyle = "washRail";
    };

    browser = {
      openTerminalLinksInCmuxBrowser = true;
      interceptTerminalOpenCommandInCmuxBrowser = true;
      defaultSearchEngine = "google";
      showSearchSuggestions = true;
    };

    shortcuts = {
      bindings = {
        focusLeft = "cmd+shift+h";
        focusDown = "cmd+shift+j";
        focusUp = "cmd+shift+k";
        focusRight = "cmd+shift+l";
        toggleSplitZoom = "cmd+z";
        goToWorkspace = "cmd+s";

        nextSidebarTab = "cmd+shift+f";
        prevSidebarTab = "cmd+shift+b";

        focusBrowserAddressBar = "cmd+l";
        openBrowser = "cmd+shift+o";
      };
    };
  };
in
{
  # cmux reads cmux.json; settings.json is only a legacy fallback for keys
  # missing from it, so writing there left this configuration inert.
  xdg.configFile."cmux/cmux.json" = {
    source = jsonFormat.generate "cmux.json" cmuxSettings;
    force = true;
  };
}
