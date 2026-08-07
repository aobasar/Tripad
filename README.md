# Tripad

A menu-bar app for macOS that maps three-finger trackpad gestures to navigation
shortcuts. Personal tool: one user, one machine (MacBook Air, arm64). Not
distributed, not notarized, no App Store.

## Gestures

| Gesture | Action | Keys posted |
| --- | --- | --- |
| 3 fingers ← / → | Switch tabs | `⌃⇧Tab` / `⌃Tab` |
| 3 fingers ↑ / ↓ | Switch windows of the front app | `⌘⇧\`` / `⌘\`` |
| `⌘` held + 3 fingers ← / → | Switch apps | `⇧Tab` / `Tab` |
| `⌃` held + 3 fingers ← / → | Switch desktops (Spaces) | `←` / `→` |

The modifier you hold during a gesture is the modifier of the shortcut it fires,
so there is nothing to memorize. It also means the held modifier is never
synthesized: while `⌘` is physically down we post a bare `Tab` and the system
sees a real `⌘Tab` — the app switcher stays open, so you can keep swiping to
move several apps along.

One gesture is one step. Holding your fingers still after a swipe does not
repeat the action.

## Requirements

- macOS 14+ (developed on macOS 26.6, arm64)
- Swift 6 toolchain — Command Line Tools is enough, full Xcode is not needed
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- Native three-finger gestures turned off in System Settings → Trackpad → More
  Gestures, otherwise Mission Control and friends fire at the same time
- For desktop switching: System Settings → Keyboard → Shortcuts → Mission
  Control → "Move left/right a space" enabled (on by default)

Tripad never reads or writes system settings; the above stays a manual concern.

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
