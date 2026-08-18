{
  pkgs,
  ...
}:
{
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false;

    extensions = [
      # Extensions available in nixpkgs
      pkgs.gh-markdown-preview
      pkgs.gh-dash
      pkgs.gh-poi
      pkgs.gh-notify
      pkgs.gh-do

      # Custom extensions from overlay
    ];
  };
}
