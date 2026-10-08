# How BarPocket works

[← Back to BarPocket](../README.md)

The short answer: one slim control, one divider, and a little cooperation from Accessibility. The long answer is below.

## The hiding trick

macOS has no public API that lets one app hide another app's menu bar item. BarPocket creates two of its own status items: a visible control and a divider. When the divider becomes wide, items on its left move out of the visible part of the menu bar. When it shrinks, those native items reappear.

BarPocket places its pocket panel just below its control. This keeps the row away from a MacBook's camera cutout. The panel uses a native visual effect background and is sized to the number of discovered items.

## Finding and moving items

With Accessibility access, BarPocket reads other running apps' menu bar elements and their positions. It keeps a local inventory for opening the pocket quickly and refreshes it when the display changes or apps add and remove items.

Dragging between the pocket and menu bar asks macOS to perform the same kind of Command-drag used for native status items. BarPocket checks the resulting position before recording an item as kept visible. The saved choice is restored on a later launch when the item can be found again.

## Opening a native menu

Clicking an item in the pocket temporarily brings its real menu bar item into view and clicks that item. BarPocket watches for the resulting popup. When it can tell the popup has closed, it moves the item back. If it cannot detect a popup reliably, it leaves the item visible so the user can operate it directly.

The panel is a way to reach native status items; it is not a replacement for the menus those apps provide.

## Glyphs and privacy

This version does not capture the screen. It can display original menu bar glyphs saved on this Mac by an older BarPocket version. For a new item without a saved glyph, it shows initials. App icons from the Dock are deliberately not used as substitutes.

Choices and any existing glyph cache are stored in local app preferences. The app has no server, analytics, account, microphone use, or screen recording.

## Where the edges are

System-controlled items and apps with unusual menu implementations can resist discovery, moving, or activation. macOS updates can also change status item behavior. The fallback is **Manage icons…** or **Expand menu bar temporarily** from BarPocket's right-click menu. A normal quit restores hidden items to the native bar.
