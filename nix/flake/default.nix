# The flake's own outputs, as flake-parts modules.
#
# shared.nix first only for reading order — the module system resolves the
# arguments it publishes regardless of the position of this list.
{
  imports = [
    ./shared.nix
    ./configurations.nix
    ./treefmt.nix
    ./git-hooks.nix
    ./apps.nix
    ./packages.nix
  ];
}
