_final: prev: {
  # Japanese prose diagnostics, built here because nixpkgs does not carry it
  # and its build embeds a pinned dictionary; see nix/packages/suiko.
  suiko = prev.callPackage ../packages/suiko { };
}
