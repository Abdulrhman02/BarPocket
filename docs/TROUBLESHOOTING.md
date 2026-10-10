# Troubleshooting

[← Back to BarPocket](../README.md)

Menu bar items belong to other apps, and macOS gives each of them a slightly different personality. Here are the fixes that are worth trying before reporting a bug.

## Multiple BarPocket icons or an older copy keeps opening

Version 0.7 and later permit only one running BarPocket process per macOS user, including copies launched from different folders or preview bundle IDs. Opening a second copy activates the existing instance and exits before creating status items.

Older versions do not have this protection. Quit every older copy once before starting the current version, and keep one app in a stable location such as `/Applications/BarPocket.app`. Each instance owns a control and a divider, so multiple old copies can produce several menu bar items. The app normally restores hidden items when it quits.

The process lock is released automatically on exit or a crash. A leftover `instance.lock` file is harmless; do not delete it while BarPocket is running.

## Clicking BarPocket opens setup instead of icons

Accessibility is not enabled for the running copy. BarPocket deliberately leaves icons visible until it has access. Click **Open Accessibility Settings…** in setup, then enable BarPocket. The button requests access and opens the correct macOS page.

If it is still missing, use **Show BarPocket in Finder** in setup, then the **+** button in Accessibility to select that exact app. Permission may need to be renewed after rebuilding or moving an ad hoc signed app.

## Accessibility is on, but BarPocket cannot see icons

1. Quit BarPocket. If you have more than one copy running, quit all of them.
2. Decide which copy you actually launch. `/Applications/BarPocket.app` is a sensible permanent home.
3. Open **System Settings → Privacy & Security → Accessibility**.
4. Remove any stale BarPocket entry, add the chosen app, and enable it.
5. Reopen that same app. If the switch was already on, turn it off and on once, then reopen.

macOS ties the permission to an app's identity and location. A newly built ad hoc signed copy may need a fresh entry even when the older copy worked.

## The pocket opens, but an item is missing

- Right-click BarPocket and choose **Expand menu bar temporarily**. This shows the native items so you can find the missing one.
- Check **Settings → Manage icons…**. It lists the items BarPocket can discover through Accessibility.
- Quit and reopen the app that owns the missing menu bar item. BarPocket refreshes its inventory periodically.
- Some system items do not expose the Accessibility information BarPocket needs. Those items may stay outside its control.

BarPocket hides a group of native status items; it does not own or delete them.

## Dragging an item does nothing

Hold the item and drag it all the way to the menu bar or onto BarPocket's icon or open pocket. If the source app opens its own menu instead of allowing the drag, use **Settings → Manage icons…** and choose **Keep visible** or **Move to pocket**.

Moving an item relies on macOS accepting a Command-drag of that app's native status item. BarPocket checks the item's actual position before saving a choice, so a rejected move should not become a permanent preference.

## Clicking a pocket item leaves it visible

Some apps open menus or windows that macOS does not expose in a way BarPocket can reliably recognize. In that case, BarPocket leaves the native icon visible so you can click it directly. When you are done, move it back with **Manage icons…** or drag it onto BarPocket.

## An icon image is missing or stale

Enable both Accessibility and **Screen & System Audio Recording** for the installed BarPocket copy. Quit before moving the app; moving a running copy leaves its process at the old path. Rebuilt ad hoc copies may need their permission entries renewed; a consistent signing certificate avoids a new identity on every build.

Choose **Refresh icons** in Settings or the context menu. A new app or reopened app is detected automatically; status badges and battery artwork refresh every three seconds while the pocket is open. Faster animation frames may be skipped. Periodic status capture stops while closed; new/reopened/appearance captures and up to three initial recovery attempts can still occur. Recovery attempts are 30 seconds apart. Capture failures leave native icons visible and provide a tooltip explaining the failure. The app never shows two-letter placeholders.

## The pocket closes too quickly

Open **Settings…** from BarPocket's right-click menu and turn off **Close automatically**. You can also turn off **Open on hover** if you prefer click-only behavior.

## Launch at login did not stick

Toggle **Launch at login** off and on in BarPocket Settings, then check **System Settings → General → Login Items** for BarPocket. Keep one installed copy in a stable location.

## The app will not build

Run `xcode-select --install` if the Xcode Command Line Tools are missing. Then run `./build.sh` from the repository folder. The script writes its app and compiler cache into `dist/`, so that folder must be writable.

## Still stuck?

[Open an issue](https://github.com/Abdulrhman02/BarPocket/issues) with:

- macOS version and Mac model;
- BarPocket version (`0.8` for this experimental source release);
- the app that owns the affected menu bar item;
- what you clicked or dragged, what happened, and what you expected.

Screenshots help, but please check them for private content first.

## A saved pin changes after an app restart

BarPocket prefers stable Accessibility identifiers. Apps that do not supply one are identified by their native window ID; macOS may assign a new ID when that app restarts. Set Keep visible again in Manage icons. Battery, Wi-Fi and other supported system items use stable identifiers instead of list indexes.
