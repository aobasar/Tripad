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
| `⌘` held + 3 fingers ← / → | Switch apps, no switcher panel | none — see below |
| `⌃` held + 3 fingers ← / → | Switch desktops (Spaces) | `←` / `→` |
| `⌥` held + 3 fingers ← / → | Move focused window to the next desktop, and follow | `⌃←` / `⌃→` while dragging — lands on release |

The `⌥` row was added after the first four were working; the owner reopened a
set that had been declared closed. What stays rejected is the *shape* of the
rejected ideas, not the count: no three-finger tap, no gesture sequences
(swipe-right-then-left), no speed or distance discrimination. Modifier + swipe
is the only pattern, and `⇧` is the last free modifier.

## Design decisions and why

**The modifier of a gesture matches the modifier of the shortcut it triggers.**
`⌘`+swipe means "apps", `⌃`+swipe means "desktops". Nothing to memorize.

**Held modifiers are never synthesized.** Where a shortcut is posted, we send
the bare key and let it merge with what the user is already holding. This
sidesteps the classic bug where a synthesized modifier collides with a
physically held one and produces the wrong chord.

**App switching does not use `⌘Tab`.** The original design posted `Tab` while
`⌘` was held and treated the switcher panel staying open as a free feature. In
use it was not one: the owner wants the app to change immediately, not to aim
at a panel. The panel is inseparable from `⌘Tab`, so `AppSwitcher` activates
the next app itself through `NSWorkspace` instead.

The ring is ordered by process id — launch order — deliberately, not by most
recent use. With no panel to look at, an MRU cycle has no visible state and
just bounces between the last two apps; a fixed ring means repeated swipes walk
the whole list and wrap around, which is what makes "keep swiping until you get
there" work.

**Direction is literal: swipe left, go left.** The inverted arrangement — the
desktop following the fingers, the way natural scrolling moves the page rather
than the viewport — was built at the owner's request, lived in for a while, and
then reverted because it never stopped feeling wrong in use. Do not re-propose
it. Moving a window follows the same rule, and the two must stay in step.

**`WindowMover` drags the window; it does not reassign it.** The direct route
was built first and measured to be inert: `CGSMoveWindowsToManagedSpace` returns
without complaint and the window's space, read straight back, is unchanged —
`space now 3, wanted 64` in the log. Reassigning another app's windows to a
Space is reserved for tools that inject into Dock.app with SIP partially
disabled. Do not spend another afternoon on the private route: the symbols
resolve, the calls are accepted, and nothing happens.

What works is doing it the way a person does — press on the title bar, nudge to
start a drag, switch desktop, release. All public API, so Tripad depends on no
undocumented symbols anywhere.

Details that are load-bearing:

- The grab point is the window's **top centre, 4px down** (`grabDepth`). The
  first attempt was a fixed offset just right of the traffic lights, which is
  title bar in most apps but lands on a toolbar control in several. Top centre
  is emptier — apps put their controls in a row lower down. 4px and not more:
  Safari's URL bar reaches high enough that 8px in hits it. Not less either, or
  the click lands on the resize border and resizes instead of dragging.
- **The cursor cannot be hidden during the drag.** `NSCursor.hide()` and
  `CGDisplayHideCursor` were both tried and neither does anything: cursor
  visibility belongs to the frontmost app, and Tripad is a background agent.
  Activating it to earn that right would steal focus from the window being
  moved. The visible teleport stays.
- **The desktop switch has to wait for `⌥` to come up.** `⌃→` posted while `⌥`
  is physically held is ignored: the WindowServer matches its space shortcut
  against the real keyboard state, not only the flags on the synthetic event.
  The keys go out correctly and nothing happens. The mouse keeps hold of the
  window during the wait, so this reads as intentional rather than laggy.
- That `⌃→` is posted with `mergingHeld: false`, since the held `⌥` is not part
  of the chord and would turn it into "move by word".
- `CGSManagedDisplaySetCurrentSpace` was tried as a way to dodge the wait. It is
  worse than useless: it does not move the screen, it only rewrites the
  *reported* current space, after which the system disagrees with itself about
  which desktop is showing.

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

**A synthetic arrow key needs the flags real hardware sends.** Mission
Control's "Move left a space" is registered with the modifier mask `0x840000` —
fn + control — and a laptop's arrow keys report both the secondary-fn and the
numeric-pad bit. A plain `⌃←` was posted correctly and provably ignored until
`KeyCode.inherentFlags` added those bits. Check
`~/Library/Preferences/com.apple.symbolichotkeys.plist` before blaming the tap:
an entry with `enabled` and no `value` is on and using the system default.

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

README has the full list with what to set each row to and a `defaults` one-liner
to verify it. Tripad does not read or write system settings; that stays a manual
concern.

Verified state on this machine: every `TrackpadThreeFinger*` key is `0` in both
`com.apple.AppleMultitouchTrackpad` and
`com.apple.driver.AppleBluetoothMultitouch.trackpad`, full-screen switching has
been moved to four fingers, and symbolic hotkeys 79/81 ("Move left/right a
space") are enabled. Three-finger drag under Accessibility → Pointer Control is
the nastiest of these: it eats three-finger movement before anything else sees
it, so Tripad goes dead with no other symptom.

## Build

No full Xcode on this machine — Command Line Tools only (Swift 6.3, macOS 26.6).
Build with SwiftPM plus a `build.sh` that assembles `Tripad.app` by hand
(`Info.plist` with `LSUIElement`, signed with a stable local identity). arm64 only.

**The owner runs this on more than one Mac**, and README carries the step-by-step
for setting up a new one. Three things bite there, all of them recorded in that
section — keep it current, it is the only part of the docs read while away from
this machine:

- The `Tripad Local` certificate is generated fresh per machine, so Accessibility
  must be granted again on the new one.
- The conflicting trackpad gestures are on by default on a fresh install, and a
  new Mac feels like the app is broken until they are turned off.
- The Accessibility grant is per path as well as per signature. Testing out of
  `build/` and then copying to `/Applications` leaves two indistinguishable
  Tripad rows in the permission list. The installed copy is `/Applications`;
  `build/Tripad.app` is an artifact, not an installation.

The app on this machine runs from `/Applications/Tripad.app`.

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

Launch at login stays out of the app, but README points at System Settings →
General → Login Items for it, which is the right place for a tool that already
leaves every other system setting alone.

## Conventions

Code and code comments in English. Conversation with the owner in Turkish.
