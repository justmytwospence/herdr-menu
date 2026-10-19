# HerdrMenu

A macOS menu bar app for [herdr](https://herdr.dev), in the style of Rectangle. Click to split, focus, resize, swap, zoom or close panes, or to open tabs and workspaces. Each item shows herdr's default keybind, so the menu doubles as a cheat sheet.

It runs the `herdr` CLI (`~/.local/bin/herdr`) rather than faking keystrokes, so it acts on the focused pane and doesn't need Accessibility permission.

## Build and run

```sh
./build.sh
open HerdrMenu.app
```

Needs the Xcode command line tools (`swiftc`).

## Notes

- The keybinds shown are herdr's defaults (prefix `ctrl+b`). They aren't read from `config.toml`.
- The menu bar icon is herdr's logo, converted to a template image (`sheep.png`).
