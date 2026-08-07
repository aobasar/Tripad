# Tripad

A small personal macOS menu-bar app that maps three-finger trackpad gestures to
navigation shortcuts. Single user (the repo owner), personal machine, MacBook Air
(arm64). Not a product — no distribution, no App Store, no notarization.

Status: **scaffold built and compiling** (v0.1.0). Gesture tap, key posting,
menu bar UI, permission handling and `build.sh` are in place; real-trackpad
behaviour is not validated yet. Next step is tuning against actual use.

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

**One gesture equals one step.** Holding fingers still after a swipe does not
repeat the action.

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
