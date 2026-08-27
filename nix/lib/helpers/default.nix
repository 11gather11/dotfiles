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
}
