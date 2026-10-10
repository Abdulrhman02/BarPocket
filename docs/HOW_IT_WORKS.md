# How BarPocket works

[← Back to BarPocket](../README.md)

The short answer: one slim control, one divider, and a little cooperation from Accessibility. The long answer is below.

## The hiding trick

macOS has no public API that lets one app hide another app's menu bar item. BarPocket creates two of its own status items: a visible control and a divider. When the divider becomes wide, items on its left move out of the visible part of the menu bar. When it shrinks, those native items reappear.

BarPocket places its pocket panel just below its control. This keeps the row away from a MacBook's camera cutout. The panel uses a native visual effect background and is sized to the number of discovered items.

## Finding and moving items

With Accessibility access, BarPocket reads other running apps' menu bar elements and their positions. It keeps a local inventory for opening the pocket quickly and refreshes it when the display changes or apps add and remove items.

Dragging between the pocket and menu bar asks macOS to perform the same kind of Command-drag used for native status items. BarPocket checks the resulting position before recording an item as kept visible. The saved choice is restored after native positions settle on a later launch, with bounded position retries. System items get distinct names such as Battery and Wi-Fi in Manage icons.

## Opening a native menu

Clicking an item in the pocket temporarily brings its real menu bar item into view and clicks that item. BarPocket watches for the resulting popup. When it can tell the popup has closed, it moves the item back. If it cannot detect a popup reliably, it leaves the item visible so the user can operate it directly.

The panel is a way to reach native status items; it is not a replacement for the menus those apps provide.

## Glyphs and privacy

The app captures native menu bar window stills at best resolution, retaining alpha transparency and coloured artwork. WindowServer menu bar window discovery is resolved dynamically; missing symbols fail safely. AX geometry matches the native window because macOS can proxy third-party status windows through Control Center. Native captures work with offscreen items without staging them or photographing wallpaper. This uses undocumented window discovery and a deprecated CoreGraphics capture API; the ScreenCaptureKit shareable window list did not expose offscreen status windows in our tests.

Transparent margins are cropped without removing coloured badges. Artwork retains its original native menu bar point dimensions; cropping transparent margins does not enlarge the battery or other small glyphs. The pocket uses native popover material. Monochrome icons use AppKit template tinting. In dark appearance, neutral dark ink in mixed-colour images is lifted while coloured pixels, badge lettering, alpha, and pixel/point dimensions remain intact.

Images are cached by item identity, owner PID and appearance. Missing/reopened items refresh automatically; closed items are pruned. While the pocket is visible, stills refresh every three seconds, and opening it refreshes immediately. Periodic status refresh stops while closed; initial/new/reopened/appearance captures can still happen. Failed initial captures retry after 30 seconds, up to three total attempts. A manual refresh resets the retry budget. This samples changing status; it does not reproduce every animation frame. Failed refreshes keep the previous image; failed initial capture keeps the native group accessible. Refresh icons retries explicitly.

Accessibility and screen-capture permission are both needed for the pocket. Permission loss restores native visibility. The OS may show a capture indicator and renewed consent prompts, even though this is still capture. No video/audio stream, network service or analytics is used.

## Layout and movement

The icon row keeps physical menu bar order in both LTR and RTL interfaces; button tags identify the original item independently of language direction. Native window discovery is shared by icon capture and Command-drag targeting. Drag endpoints use the native window’s global Y coordinate, including negative coordinates on upper displays. Hiding targets the divider’s left edge; restoring targets its right edge. The isolated layout/drag test renders both appearance modes and records event coordinates without posting user input.

## Stable identity

A unique AXIdentifier identifies an item across list reorderings and app restarts. Otherwise its native window ID identifies it for the owning app’s current session. Duplicate identifiers are not accepted as unique; process collisions are disambiguated. Cached owner PID and AX object identity are also checked before image reuse. Closed owners are pruned. For apps without a stable identifier, a new native window ID can require setting a saved pin again after that app restarts.

## Activation lifetime

Menu detection uses popup window layers and coordinates anchored beneath the clicked item, including negative display origins. Ordinary app windows do not keep the pocket locked. Only initially detected popup IDs are tracked; the wait is bounded to 60 seconds. Permission loss ends the wait and keeps the native icon reachable.
