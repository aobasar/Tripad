import AppKit

/// Moves the focused window to the neighbouring desktop by doing what a person
/// would do: grab it by the title bar and switch desktops while holding it.
///
/// The direct route was tried first and does not work. `CGSMoveWindowsToManagedSpace`
/// runs without complaint and changes nothing — the window's space, read back
/// immediately after, is still the old one. That matches how the platform
/// treats this class of operation: window managers that move windows between
/// Spaces need code injected into Dock.app and SIP partially disabled. An
/// ordinary signed app does not get to reassign another app's windows.
///
/// Dragging is the supported path, so this drives it: press on the title bar,
/// nudge to start the drag, wait for `⌥` to come up, post `⌃→`, then release on
/// the far side. Everything here is public API.
@MainActor
enum WindowMover {

    /// How far below the top edge to grab a window, grabbed at its horizontal
    /// centre.
    ///
    /// The first attempt was a fixed offset just right of the traffic lights,
    /// which is title bar in most apps but lands on a toolbar control in
    /// several. The top-centre strip is emptier: apps put their controls in a
    /// row lower down, and the middle of the very top is left alone.
    ///
    /// Kept deliberately shallow: Safari's URL bar reaches high enough that 8px
    /// in lands on it, and there is only a thin strip above. Do not go below
    /// this either — the outermost few pixels are the resize border, and
    /// grabbing there resizes the window instead of moving it.
    private static let grabDepth: CGFloat = 4

    /// How long to let the desktop transition finish before letting go.
    private static let transition = Duration.milliseconds(700)

    /// How far to pull the cursor to convince the system a drag has started.
    /// Kept as small as will still register, and undone in the same breath, so
    /// what shows on screen is a flicker rather than a window sitting visibly
    /// off its mark for as long as the modifier is held.
    private static let nudge: CGFloat = 4

    /// `offset` is in desktops: +1 is the desktop to the right.
    static func move(_ offset: Int) {
        guard let window = focusedWindowID(), let frame = frame(of: window) else {
            Log.gesture.info("""
                no ordinary window in front to move \
                (frontmost app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?", privacy: .public))
                """)
            return
        }
        guard !isDragging else { return }

        let grab = CGPoint(x: frame.midX, y: frame.minY + grabDepth)
        Log.gesture.info("""
            grabbing \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?", privacy: .public) \
            window \(window, privacy: .public) at \
            \(Int(grab.x), privacy: .public),\(Int(grab.y), privacy: .public)
            """)

        beginDrag(at: grab)
        followWhenModifierReleased(offset)
    }

    // MARK: - The drag

    private static var cursorHome: CGPoint?
    private static var dragOrigin: CGPoint?
    private static var isDragging: Bool { dragOrigin != nil }

    private static func beginDrag(at point: CGPoint) {
        cursorHome = CGEvent(source: nil)?.location
        dragOrigin = point

        post(.leftMouseDown, at: point)
        // Without movement the press is a click, and a click is not a drag.
        post(.leftMouseDragged, at: CGPoint(x: point.x + nudge, y: point.y))
        // Straight back, so the window waits out the modifier where it started
        // instead of hanging a few pixels to the right the whole time.
        post(.leftMouseDragged, at: point)
    }

    private static func endDrag() {
        if let origin = dragOrigin {
            // Drag back to where the press landed before letting go. The window
            // has been following the cursor all along, so without this it keeps
            // whatever offset the nudge introduced and ends up shifted right.
            post(.leftMouseDragged, at: origin)
            post(.leftMouseUp, at: origin)
        }
        if let home = cursorHome {
            CGWarpMouseCursorPosition(home)
        }
        dragOrigin = nil
        cursorHome = nil
    }

    // The cursor visibly teleports to the window and back, and it cannot be
    // hidden from here. Both `NSCursor.hide()` and `CGDisplayHideCursor` were
    // tried and neither has any effect: cursor visibility belongs to the
    // frontmost application, and Tripad is a background agent that never comes
    // forward. Activating it to gain that right would steal focus from the very
    // window being moved, which is worse than the jump. Left visible.

    private static func post(_ type: CGEventType, at point: CGPoint) {
        let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .combinedSessionState),
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Waiting for the modifier

    private static var pendingFollow: Int?
    private static var followTimer: Timer?
    private static var followTicks = 0

    /// Switches desktop once `⌥` is up, then drops the window there.
    ///
    /// The wait is not politeness, it is necessity: `⌃→` posted while `⌥` is
    /// physically down is ignored. The WindowServer matches its space shortcut
    /// against the real keyboard state, not just the flags on the synthetic
    /// event — the keys go out correctly and nothing happens. The window stays
    /// held by the mouse in the meantime, so the drag survives the wait.
    private static func followWhenModifierReleased(_ offset: Int) {
        pendingFollow = offset
        followTicks = 0
        guard followTimer == nil else { return }

        followTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            Task { @MainActor in
                followTicks += 1
                let stillHeld = CGEventSource.flagsState(.combinedSessionState)
                    .contains(.maskAlternate)

                if !stillHeld, let offset = pendingFollow {
                    stopWaiting()
                    await switchDesktopAndDrop(offset)
                } else if followTicks > 80 {
                    // ~5s. Do not leave the mouse button held down for ever.
                    Log.gesture.info("gave up waiting for the modifier to come up")
                    stopWaiting()
                    endDrag()
                }
            }
        }
    }

    private static func stopWaiting() {
        followTimer?.invalidate()
        followTimer = nil
        pendingFollow = nil
    }

    private static func switchDesktopAndDrop(_ offset: Int) async {
        KeyPoster.post(
            offset > 0 ? .rightArrow : .leftArrow,
            adding: .maskControl,
            mergingHeld: false
        )
        try? await Task.sleep(for: transition)
        endDrag()
        Log.gesture.info("dropped the window on the next desktop")
    }

    // MARK: - Finding the window

    /// The frontmost app's frontmost ordinary window.
    ///
    /// `CGWindowListCopyWindowInfo` returns windows front to back. Layer 0
    /// filters out panels, menus and the desktop. Window titles would need
    /// Screen Recording permission; ids and bounds do not.
    private static func focusedWindowID() -> CGWindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return onScreenWindows().first {
            $0[kCGWindowOwnerPID as String] as? pid_t == pid
        }?[kCGWindowNumber as String] as? CGWindowID
    }

    private static func frame(of window: CGWindowID) -> CGRect? {
        guard let bounds = onScreenWindows().first(where: {
            $0[kCGWindowNumber as String] as? CGWindowID == window
        })?[kCGWindowBounds as String] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
    }

    private static func onScreenWindows() -> [[String: Any]] {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return windows.filter { $0[kCGWindowLayer as String] as? Int == 0 }
    }
}
