{ pkgs, ... }:
{

  # Define the sudo PAM stack explicitly so the authentication order is
  # controlled (nix-darwin's typed options fix the order and let Touch ID win
  # before Apple Watch is ever offered).
  #   1. pam-reattach: reattach to the user's GUI session so Touch ID / Apple
  #      Watch work inside a multiplexer pane.
  #   2. pam_tid.so: Touch ID first, so an open MacBook authenticates by finger.
  #   3. pam-watchid: Apple Watch as the fallback when Touch ID is unavailable.
  security.pam.services.sudo_local.text = ''
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
    auth       sufficient     pam_tid.so
    auth       sufficient     ${pkgs.pam-watchid}/lib/pam_watchid.so
  '';

}
