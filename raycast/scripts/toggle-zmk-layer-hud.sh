#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Keymap HUD
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⌨️
# @raycast.packageName ZMK

# Documentation:
# @raycast.description Show or hide zmk-layer-hud for the Ergonaut One

# Raycast runs scripts without the login shell's PATH, so the HUD is called by its full path
hud="$HOME/.local/bin/zmk-layer-hud"
panel="$HOME/.local/share/zmk-layer-hud/host/macos/panel.py"

if pgrep -f "$panel" >/dev/null; then
  pkill -f "$panel"
  # The panel handles SIGTERM only when its Cocoa run loop next wakes, which may be never
  for _ in 1 2 3 4; do
    pgrep -f "$panel" >/dev/null || break
    sleep 0.5
  done
  pkill -KILL -f "$panel"
  echo "Keymap HUD hidden"
else
  "$hud" start >/dev/null 2>&1
  echo "Keymap HUD shown"
fi
