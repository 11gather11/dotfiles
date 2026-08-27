# The gate that keeps `gh pr create` behind the codex-review skill.
#
# Defined here rather than beside the hook that installs it so the flake check
# in nix/flake/checks.nix tests the very derivation that ships. Testing the
# bare .sh instead would leave the wrapper untested, and the wrapper is where
# PATH and the bash options are decided — a gate that fails open because jq was
# missing, or that exits 1 instead of 2, is a gate that is not there.
#
# errexit is deliberately absent: the script reads a HEAD that may legitimately
# not exist, and under `set -e` that assignment would end the script with a
# status Claude Code reads as "hook broke, carry on" rather than as a block.
{ pkgs }:
pkgs.writeShellApplication {
  name = "claude-codex-review-gate";
  runtimeInputs = with pkgs; [
    jq
    git
  ];
  bashOptions = [
    "nounset"
    "pipefail"
  ];
  text = builtins.readFile ../../modules/home/programs/claude-code/codex-review-gate.sh;
}
