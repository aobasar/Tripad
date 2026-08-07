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

| File | Role |
| --- | --- |
| `Sources/Tripad/GestureTap.swift` | Event tap, touch tracking, swipe detection |
| `Sources/Tripad/GestureAction.swift` | Gesture → shortcut map, also the menu's help text |
| `Sources/Tripad/KeyPoster.swift` | Posts key events, merging held modifiers |
| `Sources/Tripad/MenuBarController.swift` | Status item and menu |
| `Sources/Tripad/AppDelegate.swift` | Wiring, permission polling |
| `Sources/Tripad/Accessibility.swift` | Trust check and prompt |
| `Sources/Tripad/Settings.swift` | The single persisted flag |

Swipe sensitivity is the `threshold` constant in `GestureTap.swift`
(normalized trackpad units, `0.08` by default).

## Out of scope

Launch at login, a preferences window, per-app mappings, gesture sequences,
three-finger tap, auto-update, any persistence beyond the enabled flag.

## Status

Scaffold complete and building: gesture detection, key posting, menu bar UI and
permission handling are all in place. Not yet validated against real trackpad
use — thresholds and per-app behaviour may need tuning.
