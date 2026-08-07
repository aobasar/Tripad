# Tripad

A menu-bar app for macOS that maps three-finger trackpad gestures to navigation
shortcuts. Personal tool: one user, one machine (MacBook Air, arm64). Not
distributed, not notarized, no App Store.

## Gestures

| Gesture | Action | Keys posted |
| --- | --- | --- |
| 3 fingers ← / → | Switch tabs | `⌃⇧Tab` / `⌃Tab` |
| 3 fingers ↑ / ↓ | Switch windows of the front app | `⌘⇧\`` / `⌘\`` |
| `⌘` held + 3 fingers ← / → | Switch apps, no switcher panel | none |
| `⌃` held + 3 fingers ← / → | Switch desktops (Spaces) | `←` / `→` |
| `⌥` held + 3 fingers ← / → | Move the focused window to the next desktop, and follow it — lands when you release `⌥` | `⌃←` / `⌃→` |

The modifier you hold says what you are switching: `⌘` for apps, `⌃` for
desktops. Where a shortcut is posted, only the bare key is sent and it merges
with the modifier you are already holding, so a synthesized modifier can never
collide with a physical one.

Two deliberate departures from the obvious:

- **App switching does not use `⌘Tab`.** The switcher panel is inseparable from
  that shortcut, and the point of the gesture is to change app immediately, not
  to aim at a panel. Tripad activates the next app itself. The order is fixed
  (launch order) rather than most-recently-used: with no panel to look at, an
  MRU cycle bounces between the last two apps, while a fixed ring lets repeated
  swipes walk the whole list and wrap around.
- **Direction is literal**: swipe left, go left. The other arrangement — the
  desktop following your fingers, the way natural scrolling moves the page
  rather than the viewport — was tried for a while and did not survive use.
  Moving a window reads the same way: swipe left and the window goes left.
- **Moving a window between desktops is done by dragging it**, the way a person
  would: grab the title bar, switch desktop while holding, let go. The direct
  route was tried first and does not work — `CGSMoveWindowsToManagedSpace` runs
  without complaint and changes nothing, as reading the window's space straight
  back after the call showed. Reassigning another app's windows to a Space is
  reserved for tools that inject into Dock.app with SIP partially disabled.
  Dragging needs no private API at all, so Tripad uses none.

  The consequence you can see: the cursor jumps to the window's title bar for
  the duration, and the desktop changes when you **release `⌥`**, not when you
  swipe. That is not a delay for its own sake — `⌃→` is ignored while `⌥` is
  physically held, because the WindowServer matches its space shortcut against
  the real keyboard state and not just the flags on a synthetic event. The mouse
  keeps hold of the window while it waits.

One gesture is one step. Holding your fingers still after a swipe does not
repeat the action.

## Requirements

- macOS 14+ (developed on macOS 26.6, arm64)
- Swift 6 toolchain — Command Line Tools is enough, full Xcode is not needed
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- The system settings below

## System settings Tripad depends on

macOS claims three-finger swipes for itself. Every one of those built-in
gestures has to be moved to four fingers or turned off, or it fires at the same
time as Tripad and you get both — a desktop switch *and* Mission Control.

Tripad never reads or writes these; it is a one-time manual setup.

**System Settings → Trackpad → More Gestures**

| Row | Set it to | Why |
| --- | --- | --- |
| Swipe between pages | *Scroll left or right with two fingers* | Otherwise three-finger left/right pages back and forward in the browser as well as switching tabs |
| Swipe between full-screen applications | *Swipe with four fingers*, or off | Collides with every horizontal three-finger gesture |
| Mission Control | *Swipe up with four fingers*, or off | Collides with three fingers up |
| App Exposé | *Swipe down with four fingers*, or off | Collides with three fingers down |

Notification Centre, Launchpad and Show Desktop use two-finger, four-finger or
pinch gestures and do not collide — leave them alone.

**System Settings → Accessibility → Pointer Control → Trackpad Options**

"Use trackpad for dragging" must not be set to *Three Finger Drag*. It swallows
three-finger movement before anything else sees it, so Tripad goes completely
dead with no other symptom.

**System Settings → Keyboard → Keyboard Shortcuts → Mission Control**

"Move left a space" and "Move right a space" must be **enabled** — these are the
shortcuts the desktop gestures post. On by default.

To check the whole lot without clicking through the UI:

```sh
for domain in com.apple.AppleMultitouchTrackpad \
              com.apple.driver.AppleBluetoothMultitouch.trackpad; do
  echo "$domain"
  defaults read "$domain" 2>/dev/null |
    grep -E "ThreeFinger(HorizSwipe|VertSwipe|Drag)"
done
```

Every value printed must be `0`. The two domains are the built-in trackpad and
an external Magic Trackpad; System Settings only writes the one for the device
whose panel you are looking at, so with both connected, set both.

## Build and run

```sh
./build.sh
open build/Tripad.app
```

`build.sh` compiles with SwiftPM, assembles `build/Tripad.app` by hand
(`Info.plist` with `LSUIElement`, so no Dock icon), and signs it.

On first launch the app asks for Accessibility permission and then polls every
two seconds, so you can grant it without relaunching. Until it is granted the
menu says so instead of failing silently.

To keep it around, copy `build/Tripad.app` to `/Applications` yourself.

## Signing

macOS keys the Accessibility grant to the code signature. A plain ad-hoc
signature is identified by its cdhash, which changes on every build — the
permission would have to be re-approved each time. So `build.sh` creates a
self-signed certificate named **Tripad Local** in the login keychain on first
run and signs with that. The designated requirement becomes bundle id +
certificate, which is stable across rebuilds.

The one-time setup may ask for your login password when the certificate is
marked as trusted for code signing. If that step fails, the script says so and
falls back to ad-hoc signing; you can create the certificate manually with
Keychain Access → Certificate Assistant → Create a Certificate (self-signed,
Code Signing), naming it `Tripad Local`.

After changing the signing identity, macOS may hold on to the stale
Accessibility entry: remove Tripad in System Settings and add it again.

## How it works

Detection is a public `CGEventTap` on `NSEventTypeGesture`, not the private
MultitouchSupport.framework. Each event is rebuilt with `NSEvent(cgEvent:)`, the
touching contacts are read with `touches(matching:in:)`, exactly three are
required, and the direction comes from the average normalized movement of the
group past a threshold.

| Path | Role |
| --- | --- |
| `Sources/Tripad/GestureTap.swift` | Event tap, touch tracking, swipe detection |
| `Sources/Tripad/GestureAction.swift` | Gesture → shortcut map, also the menu's help text |
| `Sources/Tripad/KeyPoster.swift` | Posts key events, merging held modifiers |
| `Sources/Tripad/AppSwitcher.swift` | Direct app switching, no `⌘Tab` panel |
| `Sources/Tripad/WindowMover.swift` | Moves a window between desktops by driving a title-bar drag |
| `Sources/Tripad/MenuBarController.swift` | Status item and menu |
| `Sources/Tripad/AppDelegate.swift` | Wiring, permission polling |
| `Sources/Tripad/Accessibility.swift` | Trust check and prompt |
| `Sources/Tripad/Settings.swift` | The single persisted flag |
| `Sources/Tripad/Log.swift` | Logger handles |
| `Assets/` | `icon-source.png` (original art) and `AppIcon.png` (1024 master) |
| `scripts/make-appicon.swift` | Regenerates the master from the source art |

Swipe sensitivity is the `threshold` constant in `GestureTap.swift` — `0.08` of
the trackpad's width by default.

Three things about the event stream cost real debugging time and are worth
knowing before touching `GestureTap`:

- Gesture events **without any touch payload** are interleaved with the real
  ones. Reading them as "fingers lifted" resets tracking every other event, and
  no swipe ever reaches the threshold. Events whose `touches(matching: .any)` is
  empty are skipped.
- `normalizedPosition` is `0...1` on both axes, but the trackpad is much wider
  than it is tall, so the same physical movement yields a larger `dy` than `dx`.
  Compared raw, nearly every swipe reads as vertical. `dy` is rescaled by the
  device aspect ratio before the axes are compared.
- An `NSEvent` rebuilt from a gesture `CGEvent` reports **no modifier flags**.
  The held modifier is read live from `CGEventSource.flagsState`, the same
  source `KeyPoster` merges into what it sends.

A fourth one lives on the posting side: a synthetic arrow key needs the flags
real hardware sends. Mission Control's "Move left a space" is registered with
the mask `0x840000` — fn + control — and a laptop arrow key reports both the
secondary-fn and numeric-pad bits. `⌃←` was posted correctly and silently
ignored until `KeyCode.inherentFlags` supplied them.

## Icon

`Assets/icon-source.png` is the original artwork; it is full-bleed with opaque
black corners. `scripts/make-appicon.swift` lays it out on the macOS icon grid
(824 of a 1024 canvas) and clips it to a rounded square so the corners are
actually transparent, producing `Assets/AppIcon.png`. `build.sh` turns that
master into `AppIcon.icns` on every build. Re-run the script by hand only when
the artwork changes:

```sh
swift scripts/make-appicon.swift Assets/icon-source.png Assets/AppIcon.png
```

The menu-bar item deliberately keeps an SF Symbol instead: a glossy colour icon
does not read at 18 pt and would not follow the light/dark menu bar.

## When something does not work

The app is invisible and permission-gated, so it reports what it is doing to the
unified log:

```sh
log show --last 5m --predicate 'subsystem == "com.aobasar.Tripad"' --info
```

At launch it records whether Accessibility is trusted and whether the event tap
installed. Every recognised swipe is logged with its direction, deltas and the
modifiers that were held — enough to tell "not detected" apart from "detected
and mapped to something else". Add `--debug` for per-event touch counts and the
keys being posted.

## Out of scope

Launch at login, a preferences window, per-app mappings, gesture sequences,
three-finger tap, auto-update, any persistence beyond the enabled flag.

## Status

Scaffold complete and building: gesture detection, key posting, menu bar UI and
permission handling are all in place. Not yet validated against real trackpad
use — thresholds and per-app behaviour may need tuning.
