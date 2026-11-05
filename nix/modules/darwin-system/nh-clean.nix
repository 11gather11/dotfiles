{ pkgs, ... }:
{
  # Runs as root so it can remove the system generations as well as the user's:
  # home-manager's programs.nh.clean runs as the user and never could, and those
  # root-owned generations are most of what fills the store.
  launchd.daemons.nh-clean = {
    command = "${pkgs.lib.getExe pkgs.nh} clean all --keep-since 30d";
    # launchd starts daemons with a bare PATH, and nh shells out to `nix`.
    # Determinate Nix installs it in the default profile rather than anywhere
    # nix-darwin puts on PATH (nix.enable is false), so without this every run
    # failed with "No output from nix --version command" and nothing was
    # collected. Strings are taken as-is, hence the explicit bin. This replaces
    # launchd's default PATH, so the system directories go back in: the
    # collector finds runtime roots with /usr/sbin/lsof.
    path = [
      "/nix/var/nix/profiles/default/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
    # As root, nix opens the store directly and the deletes come from this job.
    # macOS refuses to remove an .app bundle that has been launched
    # (com.apple.macl), and the collector stops at the first such failure.
    # determinate-nixd holds Full Disk Access, granted by hand in System
    # Settings because TCC cannot be declared; App Management alone was not
    # enough. Going through the daemon makes it the one doing the deletes.
    environment.NIX_REMOTE = "daemon";
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
