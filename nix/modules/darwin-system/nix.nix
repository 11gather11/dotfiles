{
  # allowUnfree is set where the nixpkgs instance is created, in flake.nix's
  # mkPkgs. nix-darwin asserts against nixpkgs.config being set here as well,
  # because an externally created instance has already been evaluated by then
  # and the setting would be silently ignored.

  # Disable nix-darwin's Nix management (using Determinate Nix)
  # Note: Nix settings are managed via /etc/nix/nix.custom.conf instead
  # This file should be manually configured with trusted-users and substituters
  nix.enable = false;
}
