{ pkgs, ... }:
{
  home.packages = with pkgs.llm-agents; [
    cursor-agent
    grok
    # Agent multiplexer: runs inside the existing terminal, survives detach,
    # and exposes a socket API that agents themselves can drive
    herdr
    opencode
    copilot-cli
    coderabbit-cli
    rtk
  ];
}
