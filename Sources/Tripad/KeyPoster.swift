import CoreGraphics

/// Virtual key codes we post. ANSI layout positions, layout-independent.
enum KeyCode: CGKeyCode {
    case tab = 0x30
    case grave = 0x32
    case leftArrow = 0x7B
    case rightArrow = 0x7C
}

enum KeyPoster {

    /// Modifiers we are willing to carry over from the keyboard's real state.
    /// Anything else (caps lock, fn, numeric pad bits) would only confuse the
    /// receiving app.
    private static let carriedFlags: CGEventFlags = [
        .maskCommand, .maskControl, .maskShift, .maskAlternate,
    ]

    /// Posts one key press, starting from the modifiers the user is physically
    /// holding and adding `extraFlags` on top.
    ///
    /// The merge is the point: for the app switcher the user is already holding
    /// `⌘`, so we post a bare `Tab` (or `Tab` + a synthetic `⇧`) and the system
    /// sees a genuine `⌘Tab` / `⌘⇧Tab`. Replacing the flags instead of adding to
    /// them would drop the held `⌘` and close the switcher.
    static func post(_ key: KeyCode, adding extraFlags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let held = CGEventSource.flagsState(.combinedSessionState).intersection(carriedFlags)
        let flags = held.union(extraFlags)

        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: key.rawValue,
                keyDown: isDown
            ) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
