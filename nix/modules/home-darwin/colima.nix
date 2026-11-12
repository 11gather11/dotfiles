{
  config,
  pkgs,
  ...
}:
let
  # How long the VM must sit with no running container before it is stopped,
  # and how often that is checked.
  idleMinutes = 30;
  checkIntervalSeconds = 300;

  # Colima has no idle shutdown of its own, and its VM keeps the whole memory
  # it was given (8GiB here) resident or in swap for as long as it runs, even
  # with nothing in it. Forgetting `colima stop` once left the Mac swapping.
  stopWhenIdle = pkgs.writeShellApplication {
    name = "colima-stop-when-idle";
    runtimeInputs = [
      pkgs.colima
      pkgs.docker-client
      pkgs.coreutils
    ];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/colima-idle"
      since_file="$state_dir/idle-since"
      mkdir -p "$state_dir"

      # A stopped VM has nothing to save; forget any earlier idle start so the
      # next `colima start` gets the full grace period.
      if ! colima status >/dev/null 2>&1; then
        rm -f "$since_file"
        exit 0
      fi

      # `docker build` runs inside dockerd without a container, so an empty
      # `docker ps` alone would stop the VM in the middle of a long build. The
      # guest's 5-minute load average catches that.
      containers=$(docker --context colima ps -q 2>/dev/null || echo unknown)
      load=$(colima ssh -- cut -d' ' -f2 /proc/loadavg 2>/dev/null || echo 99)

      if [ -n "$containers" ] || [ "''${load%%.*}" -ge 1 ]; then
        rm -f "$since_file"
        exit 0
      fi

      now=$(date +%s)
      [ -f "$since_file" ] || echo "$now" >"$since_file"
      since=$(cat "$since_file")

      if [ $((now - since)) -ge ${toString (idleMinutes * 60)} ]; then
        echo "$(date -Iseconds) idle for ${toString idleMinutes}m, stopping colima"
        colima stop
        rm -f "$since_file"
      fi
    '';
  };

  logDir = "${config.home.homeDirectory}/Library/Logs";
in
{
  # colima wraps lima-full, qemu and krunkit into its own PATH, so the VM stack
  # needs no companion packages here
  home.packages = [ pkgs.colima ];

  launchd.agents.colima-stop-when-idle = {
    enable = true;
    config = {
      ProgramArguments = [ "${stopWhenIdle}/bin/colima-stop-when-idle" ];
      # colima finds its VM under $XDG_CONFIG_HOME/colima, but an agent can
      # start before that variable is published to launchd. colima then falls
      # back to ~/.colima, reports the VM as stopped, and creates that
      # directory, which every later colima, the shell's too, then prefers.
      EnvironmentVariables.COLIMA_HOME = "${config.xdg.configHome}/colima";
      StartInterval = checkIntervalSeconds;
      StandardOutPath = "${logDir}/colima-stop-when-idle.log";
      StandardErrorPath = "${logDir}/colima-stop-when-idle.log";
    };
  };
}
