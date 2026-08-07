# Tripad

A small personal macOS menu-bar app that maps three-finger trackpad gestures to
navigation shortcuts. Single user (the repo owner), personal machine, MacBook Air
(arm64). Not a product — no distribution, no App Store, no notarization.

Status: **working** (v0.1.0). All four gestures verified against the real
trackpad: direction, held modifier and posted keys confirmed in the unified log.
Remaining work is tuning and polish, not bring-up.

Repo: `git@github.com:aobasar/Tripad.git` (private). Keep `README.md` and the
GitHub repo description in sync with reality whenever behaviour changes.

## Gesture map

| Gesture | Action | Keys posted |
| --- | --- | --- |
| 3 fingers ← / → | Switch tabs | `⌃⇧Tab` / `⌃Tab` |
| 3 fingers ↑ / ↓ | Switch windows of the front app | `⌘⇧\`` / `⌘\`` |
| `⌘` held + 3 fingers ← / → | Switch apps | `⇧Tab` / `Tab` (see below) |
| `⌃` held + 3 fingers ← / → | Switch desktops (Spaces) | `←` / `→` (see below) |

The gesture set is closed. No three-finger tap, no gesture sequences
(swipe-right-then-left), no speed/distance discrimination — all were considered
and rejected as unreliable or unmemorable.

## Design decisions and why

**The modifier of a gesture matches the modifier of the shortcut it triggers.**
`⌘`+swipe fires the `⌘Tab` family, `⌃`+swipe fires `⌃←/→`. Nothing to memorize.

**Consequence — no synthetic modifier flags needed.** Because the user is
already physically holding `⌘`, we post a bare `Tab` and the system sees a real
`⌘Tab`. This sidesteps the classic bug where a synthesized modifier merges with
a physically held one and produces the wrong chord. It also means the app
switcher stays open while `⌘` is down, so the user can keep swiping to move
several apps forward — a feature we get for free rather than implementing.

**Detection uses a public `CGEventTap` on gesture events**, not the private
`MultitouchSupport.framework`. Tap `NSEventTypeGesture`, rebuild with
`NSEvent(cgEvent:)`, read `touches(matching: .touching, in: nil)`, require
exactly 3 contacts, derive direction from average normalized movement.
Touch-Tab (github.com/ris58h/Touch-Tab) migrated in this same direction, which
is corroboration that the public route is the durable one.

**Three traps in that event stream**, each of which produced a silent,
symptomless failure during bring-up. Re-deriving them is expensive; they are
commented at their sites in `GestureTap.swift`:

1. *Touchless gesture events are interleaved with the real ones.* Reading them
   as "fingers lifted" resets tracking every other event and nothing ever
   reaches the threshold. Skip events whose `touches(matching: .any)` is empty.
2. *`normalizedPosition` is `0...1` on both axes, but the trackpad is not
   square.* The same physical movement produces a larger `dy` than `dx`, so
   almost every swipe reads as vertical. Rescale `dy` by
   `NSTouch.deviceSize.height / .width` before comparing axes.
3. *An `NSEvent` rebuilt from a gesture `CGEvent` carries no modifier flags.*
   `⌘`- and `⌃`-qualified gestures therefore fell through to the unqualified
   branch. Read the held modifiers live from `CGEventSource.flagsState`, which
   is also what `KeyPoster` merges into the keys it sends.

**The app logs to `subsystem == "com.aobasar.Tripad"`.** For an invisible,
permission-gated app this is the only way to tell "gesture not detected" from
"detected and mapped elsewhere"; it is what turned each of the traps above from
a guess into a measurement. Keep it.

**One gesture equals one step.** Holding fingers still after a swipe does not
repeat the action. A gap in the event stream longer than 0.4 s also ends the
gesture, so a lift that gets swallowed (by the app switcher, for instance)
cannot wedge the detector.

**The menu doubles as the help document.** The dropdown lists the gesture map as
disabled info rows, so "how did this work again?" is always answerable without
leaving the app.

**Signing must use a stable identity.** If the code signature identity changes
between builds, macOS forgets the Accessibility grant and the permission must be
re-approved on every rebuild. Solved in `build.sh`: it creates a self-signed
`Tripad Local` certificate in the login keychain once and signs with it, so the
designated requirement is `identifier + certificate leaf` rather than a cdhash.
Ad-hoc (`codesign -s -`) remains only as a loud fallback. The PKCS#12 handoff
uses `/usr/bin/openssl` on purpose — OpenSSL 3 from Homebrew writes a MAC that
`security import` rejects.

**The icon lives in `Assets/`, not in the build.** `icon-source.png` is the
original art (full-bleed, opaque corners); `scripts/make-appicon.swift` clips it
onto the macOS icon grid so the corners are transparent and writes
`AppIcon.png`. `build.sh` only does `sips` + `iconutil` on that master. The
status item keeps an SF Symbol — a colour icon does not read at 18 pt and would
ignore the light/dark menu bar.

## Conflicting system gestures

The owner has already **disabled the native three-finger gestures** in System
Settings → Trackpad → More Gestures. Tripad does not read or write system
settings; that stays a manual concern. Watch out for Mission Control, App Exposé,
"Swipe between full-screen applications", and three-finger drag under
Accessibility → Pointer Control.

Desktop switching relies on System Settings → Keyboard → Shortcuts → Mission
Control → "Move left/right a space" being enabled (on by default).

## Build

No full Xcode on this machine — Command Line Tools only (Swift 6.3, macOS 26.6).
Build with SwiftPM plus a `build.sh` that assembles `Tripad.app` by hand
(`Info.plist` with `LSUIElement`, ad-hoc signature). arm64 only.

`Tripad` is a valid Swift module name, so the module and the product share one
name — no aliasing needed. (The earlier working name `3Finger` would have
required a separate module name, since Swift identifiers cannot start with a
digit.)

## Runtime requirements

Accessibility permission only, granted manually in System Settings → Privacy &
Security → Accessibility. The app should detect its absence and say so in the
menu rather than failing silently.

## Out of scope

Launch at login, a preferences window, per-app gesture mappings, gesture
sequences, three-finger tap, auto-update, persistence beyond a single
enabled/disabled flag in `UserDefaults`.

## Conventions

Code and code comments in English. Conversation with the owner in Turkish.
