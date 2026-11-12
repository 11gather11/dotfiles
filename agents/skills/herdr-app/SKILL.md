---
name: herdr-app
description: Drives the herdr-app window and the herdr-core (`hc`) terminals it shows, and customises the app from this repository. Use when the user mentions herdr-app, hc or herdr-core, asks to change its layout, keys, theme or panels, or asks to start, read or message a terminal or agent from a herdr-app terminal (HC_TERMINAL_ID set).
---

# herdr-app

Read the manuals of the installed versions first; they change with every
release, so this skill does not copy them:

```sh
herdr-app --skill   # the window: spaces, tabs, panes, layouts
hc --skill          # herdr-core: running, reading and messaging terminals
```

This is not `herdr`, the TUI multiplexer, whose own skill applies inside a
herdr pane (HERDR_ENV=1). Both run on this machine; a terminal belongs to
the one its environment names.

## Customising the app

The app's own manual, `~/.config/herdr-app/AGENTS.md`, says to edit the files
in `~/.config/herdr-app`. Here those files are copies: keys, layouts, themes
and mods live in this repository's `herdr-app/`, and every `nix run .#switch`
copies them over whatever was edited in place. So:

1. Edit `herdr-app/` in `~/ghq/github.com/11gather11/dotfiles`; settings that
   the app also writes (fonts, theme name, option keys) are merged from
   `nix/modules/home-darwin/herdr-app.nix`.
2. Run `herdr-app-sync` to copy the change into the app, which redraws at once.
3. Check it: `herdr-app check ~/.config/herdr-app/mods/<name>` for a mod,
   `herdr-app status` for errors, `herdr-app shot <file.png>` to see it.
   A check renders only the first frame, before a mod has read anything;
   open the mod in the window before calling it done.

A shipped mod is Herdr's and is replaced on update: clone it into
`herdr-app/mods/` under a new name and point the layout at the clone.

## Harness workers

issue-harness drives its workers through its own `worker.nu`, which picks
herdr or herdr-core by where the harness runs; use that skill for them rather
than `hc` directly.
