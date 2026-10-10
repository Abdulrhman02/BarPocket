<p align="center">
  <img src="icon-1024.png" width="112" alt="BarPocket icon">
</p>

<h1 align="center">BarPocket</h1>

<p align="center">
  <strong>Your menu bar has pockets now.</strong><br>
  A small native macOS app for the icons you want nearby, just not <em>right there</em> all day.
</p>

<p align="center">
  <a href="#the-short-version">What it does</a> ·
  <a href="#get-it-running">Install</a> ·
  <a href="#the-controls">Controls</a> ·
  <a href="#honest-fine-print">Limitations</a> ·
  <a href="docs/TROUBLESHOOTING.md">Troubleshooting</a>
</p>

> [!NOTE]
> BarPocket is an early public source release. There is no notarized download yet; build it on your Mac using the steps below.

## The short version

The menu bar is prime real estate. BarPocket puts less-used items behind a slim control and shows them in a compact row **below** the menu bar, where the MacBook notch cannot eat them.

| Need | BarPocket's answer |
| --- | --- |
| A little breathing room | Items left of its divider stay out of the visible menu bar. |
| A quick peek | Click or hover over BarPocket to open the pocket. |
| An icon that has earned a permanent seat | Drag it from the pocket to the menu bar. |
| An icon that can go back in its coat closet | Drag it onto BarPocket or the open pocket. |
| A stubborn app that grabs the drag | Use **Manage icons…** in Settings. |

No subscription, no account, and no screen recording.

## What's in the pocket?

- **A row below the menu bar.** The translucent pocket opens on click or hover and can close when your pointer leaves.
- **Two-way drag and drop.** Move items between the pocket and visible menu bar; BarPocket remembers which ones you keep visible.
- **Native menus.** Click a pocket item to activate its actual menu bar item. Where macOS exposes the opened menu, BarPocket returns the item after that menu closes.
- **A manual escape hatch.** Temporarily expand the menu bar or use **Manage icons…** when an app does something unusual.
- **A few useful switches.** Choose hover opening, automatic closing, and launch at login.
- **A tidy exit.** A normal quit restores the hidden items to the menu bar.

## Watch the demo

[![BarPocket drag-and-drop preview](docs/media/barpocket-preview.gif)](https://github.com/Abdulrhman02/BarPocket/raw/refs/heads/main/docs/media/barpocket-demo.mp4)

[Watch or download the 42-second demo](https://github.com/Abdulrhman02/BarPocket/raw/refs/heads/main/docs/media/barpocket-demo.mp4).
The video uses animated interactions and actual native settings captures. Its sample icons illustrate cached glyphs; fresh items can appear as initials. The divider is omitted from the illustration for clarity; the real app uses a divider to hide native items.

## Settings

Settings start with General: native switches, short explanations, and light/dark surfaces that follow your system appearance.

<p align="center">
  <img src="docs/images/settings-light.png" width="400" alt="BarPocket settings in light appearance">
  <img src="docs/images/settings-dark.png" width="400" alt="BarPocket settings in dark appearance">
</p>

## Get it running

### Requirements

- macOS 13 Ventura or later. Development testing has been on Apple silicon with macOS 26.6.2.
- Xcode or the Xcode Command Line Tools.
- Accessibility access for BarPocket.

### Build from source

```sh
git clone https://github.com/Abdulrhman02/BarPocket.git
cd BarPocket
./build.sh
open dist/BarPocket.app
```

`build.sh` creates `dist/BarPocket.app` for your Mac's architecture and signs it locally. It does not install or replace the app already in `/Applications`.

For everyday use, quit BarPocket, copy the built app to `/Applications`, and launch **that copy**. Keep launching the same copy: macOS can treat a moved or rebuilt app as a different Accessibility entry. If you have a signing certificate, you can use it instead of the default ad hoc signature:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

There is no signed and notarized public binary yet. A Developer ID signature and notarization are needed before a download can offer the usual macOS installation experience.

### First launch

1. Open BarPocket. Its Settings window explains the permission it needs.
2. In **System Settings → Privacy & Security → Accessibility**, enable the BarPocket copy you are launching.
3. Quit and reopen BarPocket if the new permission does not take effect right away.
4. Click its menu bar icon. Your pocket should appear below the bar.

If the switch says “on” but BarPocket still cannot see items, [try the permission reset steps](docs/TROUBLESHOOTING.md#accessibility-is-on-but-barpocket-cannot-see-icons).

## The controls

| Do this | To do that |
| --- | --- |
| Click the BarPocket icon | Open or close the pocket. |
| Hover over it | Open the pocket after a short pause, if hover is enabled. |
| Click an item in the pocket | Activate its native menu bar item. |
| Hold and drag a pocket item onto the menu bar | Keep it visible. |
| Drag a visible item onto BarPocket or the open pocket | Put it back in the pocket. |
| Right-click BarPocket | Open Settings, show hidden items, expand temporarily, or quit. |
| Open **Settings → Manage icons…** | Move an item when normal dragging gets intercepted. |

Settings also has the hover, automatic closing, and launch-at-login switches. BarPocket allows one running instance per macOS user. Launching another copy activates the existing app instead of adding more menu bar items.

## Privacy, without the mystery

BarPocket asks for **Accessibility** to discover other apps' menu bar items and click or move them. It does **not** record your screen, use your microphone, send analytics, or call a server. Your visible-item choices and any old glyph cache live in local macOS app preferences.

The current version does not grab new menu bar artwork from the screen. If an older BarPocket version saved an item's original glyph on this Mac, it can reuse that glyph. Otherwise the pocket shows initials. It never swaps in the app's Dock icon and pretends that is the menu bar icon.

## Honest fine print

macOS does not provide a public API for hiding another app's status item. BarPocket uses its own status items to move a group of items out of view, then Accessibility to find and interact with them. This works well for many apps, but some protected system items and unusual menus resist moving or activation.

If an item's menu cannot be detected, BarPocket may leave its native item visible so you can click it directly. **Manage icons…** and temporary expansion are there for those cases. Details live in [How it works](docs/HOW_IT_WORKS.md) and [Troubleshooting](docs/TROUBLESHOOTING.md).

## Around the repo

| Path | What lives there |
| --- | --- |
| `main.swift` | The native AppKit app. |
| `build.sh` | A one-command local build. |
| `BarPocket.icns`, `icon-1024.png` | The graphite app icon and its source artwork. |
| `PocketLight.png`, `PocketDark.png` | Preserved monochrome brand artwork. |
| `SingleInstance.swift` | Shared per-user process lock. |
| `docs/media/` | Full landscape demo and animated README preview. |
| `generate_icon.swift` | Script that regenerates the PNG artwork. |
| `docs/` | Behavior notes and fixes for common problems. |
| `dist/` | Your local build output; ignored by Git. |

Found a bug or have an idea? [Open an issue](https://github.com/Abdulrhman02/BarPocket/issues) with your macOS version, the affected app, and a short reproduction. [Contributions are welcome](CONTRIBUTING.md). Please check screenshots for private menu bar or desktop content before attaching them.

## Development checks

```sh
python3 Tests/test_single_instance.py
```

This compiles the production process lock, verifies that a second process cannot acquire it, then checks that termination releases it for the next launch.
