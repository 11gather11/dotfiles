{ pkgs }:
# writers.writeNu with the script checked at build time. Without a check, a
# Nushell script that no longer parses is only found when something runs it,
# which for an activation script is the middle of a switch.
#
# Usage: writeNu "name" ''<script>''
let
  nu = pkgs.lib.getExe pkgs.nushell;

  # makeScriptWriter runs the check as `${check} $out`, so the script under test
  # arrives as an argument rather than on stdin, and `--debug` makes nu-check
  # exit non-zero instead of printing false.
  nuCheck = pkgs.writeShellScript "nu-check" ''
    exec ${nu} --no-config-file --commands "nu-check --debug '$1'"
  '';
in
name: body: pkgs.writers.writeNu name { check = nuCheck; } body
