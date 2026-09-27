# zmk-layer-hud

The on-screen layer HUD for the Ergonaut One. It is installed by its own script
into `~/.local/share/zmk-layer-hud` rather than by Nix, and its `update`
replaces that tree, so the fixes it needs here live in this directory and are
re-applied by hand.

## `local.patch`

- `host/hudfeed.py`
  - The host looked for a GATT service UUID the firmware module does not
    expose; it now uses the firmware's.
  - On macOS a keyboard that is already connected stops advertising, so a scan
    never finds it. With `ble.address` set, the host now takes the peripheral
    from CoreBluetooth by that UUID.
- `hud/hud.css`: hides the typed-keys strip. It needs Input Monitoring and the
  keyboard released from Karabiner-Elements, neither of which is set up here,
  and its empty box still took clicks.

Re-apply after `zmk-layer-hud update`:

```sh
patch -p1 -d ~/.local/share/zmk-layer-hud < zmk-layer-hud/local.patch
```

## Configuration

`~/.config/zmk-layer-hud/config.yaml` points `keymap:` at
`~/.config/zmk-layer-hud/ergonaut_one.yaml`: the keymap-drawer YAML from the
firmware repository with its `layout:` line replaced by
`{qmk_info_json: <repo>/config/ergonaut_one.json}`, because keymap-drawer has no
physical layout for `ergonaut_one`. Regenerate it after a keymap change. `ble:`
holds the keyboard's CoreBluetooth peripheral UUID.

`raycast/scripts/toggle-zmk-layer-hud.sh` shows and hides the panel.
