# Checks that are not linters. `nix flake check` runs these; nix/flake/git-hooks.nix
# contributes the pre-commit check alongside them.
{
  perSystem =
    { localPkgs, ... }:
    {
      # The codex-review gate is a guard, and a guard that stopped guarding
      # looks exactly like one that works: every command still succeeds. It was
      # let through unnoticed once, so its behaviour is asserted here rather
      # than confirmed by hand.
      #
      # The gate under test is the wrapped derivation the hook actually runs,
      # not the bare script — see nix/lib/helpers/codex-review-gate.nix.
      checks.codex-review-gate =
        localPkgs.runCommand "codex-review-gate-test"
          {
            nativeBuildInputs = [
              localPkgs.git
              localPkgs.jq
            ];
          }
          ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"

            bash ${../modules/home/programs/claude-code/codex-review-gate-test.sh} \
              ${localPkgs.lib.getExe (import ../lib/helpers/codex-review-gate.nix { pkgs = localPkgs; })}

            touch "$out"
          '';
    };
}
