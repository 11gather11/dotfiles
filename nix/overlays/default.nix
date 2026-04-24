final: prev:
let
  # Import all overlay files in this directory
  overlayFiles = [
    ./claude-code.nix
    ./git-now.nix
  ];

  # Apply each overlay and merge results
  applyOverlays = builtins.foldl' (acc: overlay: acc // (import overlay final prev)) { } overlayFiles;
in
applyOverlays
