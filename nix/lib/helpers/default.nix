{ lib }:
{
  # Re-export all helper modules
  activation = import ./activation.nix { inherit lib; };

  # Colour scheme names, one spelling per tool
  theme = import ./theme.nix { inherit lib; };

  # User configuration (requires config to be passed)
  mkUser = config: import ./user.nix { inherit config; };

  # The codex-review gate (requires pkgs to be passed)
  codexReviewGate = pkgs: import ./codex-review-gate.nix { inherit pkgs; };

  # writers.writeNu with the script checked at build time (requires pkgs)
  writeNu = pkgs: import ./write-nu.nix { inherit pkgs; };

  # Merges declared keys into a config file an application also writes
  # (requires pkgs to be passed)
  mergeConfig =
    pkgs:
    import ./merge-config.nix {
      inherit pkgs;
      writeNu = import ./write-nu.nix { inherit pkgs; };
    };
}
