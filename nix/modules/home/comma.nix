{
  pkgs,
  inputs,
  ...
}:
{
  # `, <command>` without the picker failing in an agent's shell: with no
  # terminal to show it on, comma died with "Failed to open tty" whenever
  # several packages provide the command, which made the missing-tools skill's
  # comma step useless to agents. See nix/packages/comma. Installed here in
  # place of nix-index-database's comma module, on both platforms.
  home.packages = [
    (pkgs.callPackage ../../packages/comma {
      inherit (inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}) comma-with-db;
    })
  ];
}
