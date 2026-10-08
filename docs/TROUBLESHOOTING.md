# Troubleshooting

[← Back to BarPocket](../README.md)

Menu bar items belong to other apps, and macOS gives each of them a slightly different personality. Here are the fixes that are worth trying before declaring an icon haunted.

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

## Icons show initials instead of their usual artwork

This is expected on a fresh install. BarPocket does not take screenshots of the menu bar. It reuses original glyphs only if an earlier version saved them locally; otherwise it shows initials. It does not replace them with the app's Dock icon.

## The pocket closes too quickly

Open **Settings…** from BarPocket's right-click menu and turn off **Close pocket when pointer leaves**. You can also turn off **Open pocket on hover** if you prefer click-only behavior.

## Launch at login did not stick

Toggle **Launch at login** off and on in BarPocket Settings, then check **System Settings → General → Login Items** for BarPocket. Keep one installed copy in a stable location.

## The app will not build

Run `xcode-select --install` if the Xcode Command Line Tools are missing. Then run `./build.sh` from the repository folder. The script writes its app and compiler cache into `dist/`, so that folder must be writable.

## Still stuck?

[Open an issue](https://github.com/Abdulrhman02/BarPocket/issues) with:

- macOS version and Mac model;
- BarPocket version (`0.6` for this source release);
- the app that owns the affected menu bar item;
- what you clicked or dragged, what happened, and what you expected.

Screenshots help, but please check them for private content first.
