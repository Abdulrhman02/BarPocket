# BarPocket

<p align="center"><img src="icon-1024.png" alt="BarPocket app icon" width="128"></p>

BarPocket is a small native macOS app that keeps menu bar items in a compact pocket. Open the pocket below the menu bar, drag items out to keep them visible, and drag them back when you want less clutter.

## Features

- Hide menu bar items behind a narrow BarPocket control.
- Open a translucent row below the menu bar by clicking or hovering.
- Drag an item from the pocket to the menu bar to keep it visible, or drag a visible item onto BarPocket to hide it again.
- Use **Manage icons…** when another app intercepts a drag.
- Save visible-item choices across launches.
- Enable or disable hover opening, automatic closing, and launch at login.
- Activate an item's native menu from the pocket. BarPocket returns it to the pocket after the menu closes when macOS lets it detect that menu.
- Restore hidden items to the menu bar on a normal quit.

## Requirements

- macOS 13 or later. Development testing has been on Apple silicon with macOS 26.6.2.
- Xcode Command Line Tools or Xcode to build from source.
- Accessibility permission to find and operate other apps' menu bar items.

## Install from source

There is not yet a notarized download. Build BarPocket on your own Mac:

```sh
git clone https://github.com/Abdulrhman02/BarPocket.git
cd BarPocket
./build.sh
open dist/BarPocket.app
```

The script creates `dist/BarPocket.app` and signs it locally with an ad hoc signature. To install it in Applications, quit BarPocket first, then copy the built app there and open that copy. Use the **same app location** when granting Accessibility permission, since macOS may treat a moved or rebuilt app as a new entry.

To sign with your own certificate instead, run:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

If macOS does not recognize the app after a rebuild, remove the old BarPocket entry in **System Settings → Privacy & Security → Accessibility**, add the app you are launching, and enable it. A Developer ID signature and notarization would be needed for a smoother public binary distribution.

## Use

1. Launch BarPocket and allow it in **System Settings → Privacy & Security → Accessibility**. Quit and reopen the app if the setting does not take effect immediately.
2. Click or hover over its menu bar icon to show the pocket below the menu bar.
3. Hold and drag an item from the pocket onto the menu bar to keep it visible. Drag a visible menu bar item onto BarPocket's icon or the open pocket to hide it.
4. Right-click BarPocket's icon for **Settings…**, **Show hidden icons**, temporary expansion, and **Quit BarPocket**.

## How it works and limitations

macOS has no public API for hiding another app's menu bar item. BarPocket uses its own status items to move items left of a divider out of view, then uses Accessibility to discover and interact with them. Some protected system items or apps with unusual menus may not move or activate reliably. Use **Manage icons…** or temporarily expand the menu bar when needed.

BarPocket does not record the screen. It does not substitute an app's Dock icon for its menu bar glyph. If a glyph was saved locally by an earlier BarPocket version, the current version can reuse it; newly discovered items are shown with initials because macOS does not expose every status item's artwork through the public APIs used here. The saved choices and any existing glyph cache stay in local app preferences.

## Build and project files

`main.swift` contains the app. `build.sh` compiles it into an app bundle using the installed macOS SDK. `BarPocket.icns` is the bundled app icon, and `icon-1024.png` is its source artwork. `generate_icon.swift` can regenerate the PNG. Build output in `dist/` is ignored by Git.

To report a problem, open a GitHub issue with your macOS version, the app whose menu bar item is affected, and the steps to reproduce it. Please avoid uploading private menu bar or desktop screenshots without checking their contents first.
