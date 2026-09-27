{
  # A Linux home has only user profiles, so the user-level job is enough here.
  # macOS cleans from a root daemon instead (darwin-system/nh-clean.nix).
  programs.nh.clean = {
    enable = true;
    dates = "weekly";
    extraArgs = [
      "--keep-since"
      "30d"
    ];
  };
}
