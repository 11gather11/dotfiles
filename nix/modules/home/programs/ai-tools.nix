{ pkgs, tgrab, ... }:
{
  home.packages = [
    # tgrab shipped an agent skill until 2026-08-04, when upstream moved the
    # contract into `tgrab --help` and dropped it. Only the skill was wired in
    # here, so the rule pointing agents at it named a binary that was never
    # installed — the whole path had been dead. Take the executable instead.
    tgrab.packages.${pkgs.stdenv.hostPlatform.system}.default
  ]
  ++ (with pkgs.llm-agents; [
    grok
  ]);
}
