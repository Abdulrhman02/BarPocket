# Contributing to BarPocket

Thanks for helping a little app make room for a lot of icons.

## Start here

1. Read the [README](README.md) and [How it works](docs/HOW_IT_WORKS.md).
2. Build locally with `./build.sh`.
3. Launch `dist/BarPocket.app` and grant that copy Accessibility access.
4. Keep changes focused and describe the menu bar behavior they affect.

The app is a small AppKit project: `main.swift` holds the runtime behavior, `build.sh` creates the bundle, and `dist/` is ignored build output.

## Reporting a bug

Include the macOS version, Mac model, BarPocket version, the app that owns the affected item, and exact reproduction steps. Explain whether the item was in the pocket or visible bar and whether you clicked, hovered, or dragged it. Check screenshots for private content before attaching them.

## Sending a change

- Keep the pocket fast to open and readable in light and dark menu bar environments.
- Preserve native status item behavior when activating menus.
- Do not add Screen Recording or replace status glyphs with Dock icons without an explicit product decision.
- Try a clean build and verify the affected behavior manually. Menu bar item behavior varies by app, so a short account of which apps you tried is more useful than a test that only mirrors the implementation.
- Describe any permission or installation change in the README and troubleshooting guide.

If you are proposing a substantial change, open an issue first so the behavior can be discussed before implementation.
