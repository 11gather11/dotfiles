{ pkgs, ... }:
{
  # Runs as root so it can remove the system generations as well as the user's:
  # home-manager's programs.nh.clean runs as the user and never could, and those
  # root-owned generations are most of what fills the store.
  launchd.daemons.nh-clean = {
    command = "${pkgs.lib.getExe pkgs.nh} clean all --keep-since 30d";
    serviceConfig = {
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 0;
          Minute = 0;
        }
      ];
      StandardOutPath = "/var/log/nh-clean.log";
      StandardErrorPath = "/var/log/nh-clean.log";
    };
  };
}
