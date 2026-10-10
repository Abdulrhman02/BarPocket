# Version 0.8 release audit

Assessment: passed for an experimental source release on the tested Mac. This is not a guarantee of compatibility with every macOS release, display arrangement or third-party menu. There is no notarized public installer.

## Fixed during review

- Capture permission regrant now works independently of Accessibility regrant; collapse checks both permissions directly.
- Native clicks use shared window discovery and both coordinate axes, including negative origins on upper/left displays.
- Popup matching excludes ordinary app windows and other displays. Activation waits are bounded; independent app windows do not hold the pocket locked.
- Window enumeration is batched during image refreshes, and optional-symbol handles are closed on failure.
- AX attribute types are checked before casting. Stable identifiers/window IDs replace positional item indexes; duplicate identities are handled safely.
- Disabled translucent black icons are accepted as artwork. Original pixel/point scale and coloured badges remain intact; monochrome/dark neutral ink follows the pocket appearance.
- Initial image recovery is limited to three attempts, 30 seconds apart. Failure keeps native items visible.
- Saved pins wait for native positions to settle and use bounded restoration retries. Manage icons distinguishes Battery, Wi-Fi, Clock and other system items.
- Permission explanation fits its setup window. Setup completion shows General settings once.
- MIT license added.

## Checks

- ARM production build and strict local code-signature verification.
- Intel source typecheck; Intel execution was not tested.
- Production lock test: cross-process exclusion, termination release and restart; duplicate installed executable launches retained one process.
- Permission harness: denied access, capture regrant while Accessibility remains enabled, revocation, failure visibility, and setup text/button layout. Harness uses simulated permission results.
- Image tests: blank rejection, faint/black transparent artwork, native dimensions, coloured badge preservation, dark neutral-ink adaptation, bounded retry policy and stable identities across reorderings.
- Production view/event harness: LTR/RTL in light/dark, fitted width, button identity/gesture attachment, both drag directions, negative-coordinate clicks and popup matching. Generated events are intercepted rather than posted.
- Live Mac: new/reopened fixture artwork, real native menu opening/dismissal/return, native restore/hide actions, saved battery pin after restart, current icon contrast and zero remaining capture failures.
- Idle observation: successful capture counter stayed unchanged while the pocket was closed after setup; no video/audio stream is implemented.

Tested on Apple silicon, macOS 26.5.2, with an external display above the laptop screen. No global system language/theme was changed.

## Remaining limits

Native discovery uses undocumented WindowServer symbols and a deprecated CoreGraphics still-capture API. A future OS change may break it; missing symbols/images must keep native visibility available. macOS 14/15 runtime, Intel runtime, full Arabic OS sessions, additional display/Spaces/full-screen arrangements and launch-at-login across logout/reboot were not verified. Some protected or unusual third-party items resist native movement/menu detection. Three-second status sampling can skip faster animations. Apps without stable AX identifiers may need pins reset after their native window IDs change on restart.
