{
  config,
  lib,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  settings = {
    auths = { };
    credsStore = "osxkeychain";
    currentContext = "orbstack";
    experimental = "enabled";
    stackOrchestrator = "swarm";
  };

  dockerConfigDir = "${config.home.homeDirectory}/.docker";
in
{
  # `docker context use` replaces config.json by renaming a temp file over it,
  # which fails with EXDEV when the path is a symlink into the store. Copying
  # leaves the file writable; each switch resets it to the values above.
  home.activation.writeDockerConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mkdir -p "${dockerConfigDir}"
    cp --no-preserve=mode,ownership ${jsonFormat.generate "config.json" settings} "${dockerConfigDir}/config.json"
    chmod 644 "${dockerConfigDir}/config.json"
  '';
}
