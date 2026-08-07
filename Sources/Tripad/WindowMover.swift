import AppKit

/// Moves the focused window to the neighbouring desktop, then follows it there.
///
/// macOS offers no public API and no default shortcut for this — the only
/// supported way is dragging a window in Mission Control. The alternatives were
/// this or simulating that drag with synthetic mouse events, which moves the
/// cursor visibly, depends on timing, and fails on windows without a title bar.
/// So this uses the private CoreGraphics Services calls that every window
/// manager on the platform uses. They need no special entitlement and no SIP
/// change; they are simply undocumented and may disappear in a macOS release.
///
/// The symbols are resolved with `dlsym` rather than declared with
/// `@_silgen_name` so their absence is a logged no-op instead of a launch-time
/// crash — when this breaks, the gesture should stop working, not the app.
@MainActor
enum WindowMover {

    /// `offset` is in desktops: +1 is the desktop to the right.
    static func move(_ offset: Int) {
        guard let cgs = CoreGraphicsServices.shared else {
            Log.gesture.error("CGS symbols unavailable, cannot move window")
            return
        }
        guard let window = focusedWindowID() else {
            Log.gesture.info("no ordinary window in front to move")
            return
        }
        guard let (spaces, currentIndex) = desktops(cgs, containing: window) else {
            Log.gesture.error("could not read the desktop list")
            return
        }

        // Desktops do not wrap: ⌃→ on the last one does nothing, and neither
        // should this.
        let targetIndex = currentIndex + offset
        guard spaces.indices.contains(targetIndex) else {
            Log.gesture.info("no desktop \(offset > 0 ? "right" : "left", privacy: .public) of this one")
            return
        }

        cgs.moveWindows(cgs.connection, [window] as CFArray, spaces[targetIndex])
        Log.gesture.info("""
            moved window \(window, privacy: .public) to desktop \
            \(targetIndex + 1, privacy: .public) of \(spaces.count, privacy: .public)
            """)

        // Follow it, or the window vanishes from under the user. The held ⌥ is
        // not part of this chord, hence mergingHeld: false.
        KeyPoster.post(
            offset > 0 ? .rightArrow : .leftArrow,
            adding: .maskControl,
            mergingHeld: false
        )
    }

    /// The frontmost app's frontmost ordinary window.
    ///
    /// `CGWindowListCopyWindowInfo` returns windows front to back. Layer 0
    /// filters out panels, menus and the desktop. Window titles would need
    /// Screen Recording permission, but ids and owners do not, and ids are all
    /// this needs.
    private static func focusedWindowID() -> CGWindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]]
        else { return nil }

        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            return id
        }
        return nil
    }

    /// The desktops of the display the window is on, left to right, plus the
    /// index of the one it currently occupies. Full-screen spaces are excluded
    /// — a window cannot be sent into one.
    ///
    /// `CGSCopyManagedDisplaySpaces` returns one entry per display, each with
    /// its own `Current Space`. Picking the first entry therefore always answers
    /// for whichever display happens to come first, which is wrong the moment a
    /// second monitor is attached. The window's own space decides instead, and
    /// the active space is only the fallback.
    private static func desktops(
        _ cgs: CoreGraphicsServices,
        containing window: CGWindowID
    ) -> ([UInt64], Int)? {
        guard let displays = cgs.copySpaces(cgs.connection)?
            .takeRetainedValue() as? [[String: Any]]
        else { return nil }

        let windowSpace = spaceOf(window, cgs)

        for display in displays {
            guard let all = display["Spaces"] as? [[String: Any]] else { continue }

            let ids = all.compactMap { space -> UInt64? in
                guard space["type"] as? Int == 0 else { return nil }
                return space["id64"] as? UInt64
            }

            let origin = windowSpace ?? (display["Current Space"] as? [String: Any])?["id64"] as? UInt64
            guard let origin, let index = ids.firstIndex(of: origin) else { continue }
            return (ids, index)
        }
        return nil
    }

    /// Which desktop a window currently lives on.
    private static func spaceOf(_ window: CGWindowID, _ cgs: CoreGraphicsServices) -> UInt64? {
        guard let copy = cgs.copySpacesForWindows else { return nil }
        // 0x7 selects every space, not just the visible one.
        let spaces = copy(cgs.connection, 0x7, [window] as CFArray)?
            .takeRetainedValue() as? [NSNumber]
        return spaces?.first?.uint64Value
    }
}

/// The three private symbols this needs, looked up once.
@MainActor
private struct CoreGraphicsServices {

    typealias ConnectionID = UInt32
    typealias CopySpaces = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    typealias MoveWindows = @convention(c) (ConnectionID, CFArray, UInt64) -> Void
    typealias CopySpacesForWindows =
        @convention(c) (ConnectionID, UInt32, CFArray) -> Unmanaged<CFArray>?

    let connection: ConnectionID
    let copySpaces: CopySpaces
    let moveWindows: MoveWindows
    /// Optional: without it the current display is guessed from the active
    /// space, which is only wrong when a window is moved on a second display.
    let copySpacesForWindows: CopySpacesForWindows?

    static let shared: CoreGraphicsServices? = {
        typealias MainConnection = @convention(c) () -> ConnectionID

        guard let mainConnection = symbol("CGSMainConnectionID").map({
                  unsafeBitCast($0, to: MainConnection.self)
              }),
              let copySpaces = symbol("CGSCopyManagedDisplaySpaces").map({
                  unsafeBitCast($0, to: CopySpaces.self)
              }),
              let moveWindows = symbol("CGSMoveWindowsToManagedSpace").map({
                  unsafeBitCast($0, to: MoveWindows.self)
              })
        else { return nil }

        return CoreGraphicsServices(
            connection: mainConnection(),
            copySpaces: copySpaces,
            moveWindows: moveWindows,
            copySpacesForWindows: symbol("CGSCopySpacesForWindows").map {
                unsafeBitCast($0, to: CopySpacesForWindows.self)
            }
        )
    }()

    /// RTLD_DEFAULT: search everything already loaded. SkyLight, which exports
    /// these, is linked in by AppKit.
    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }
}
