import CoreGraphics

/// Virtual key codes we post. ANSI layout positions, layout-independent.
enum KeyCode: CGKeyCode {
    case tab = 0x30
    case grave = 0x32
    case leftArrow = 0x7B
    case rightArrow = 0x7C

    /// Flags a real key press carries on its own, independent of what the user
    /// is holding.
    ///
    /// On a laptop keyboard an arrow key reports both the numeric-pad and the
    /// secondary-fn bit. That is not cosmetic: Mission Control's "Move left a
    /// space" is registered with the modifier mask 0x840000 — fn + control —
    /// so a synthetic `⌃←` without the fn bit simply does not match, which is
    /// exactly why desktop switching did nothing while the keys were provably
    /// being posted.
    var inherentFlags: CGEventFlags {
        switch self {
        case .leftArrow, .rightArrow: [.maskNumericPad, .maskSecondaryFn]
        case .tab, .grave: []
        }
    }
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
        let flags = held.union(extraFlags).union(key.inherentFlags)

        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: key.rawValue,
                keyDown: isDown
            ) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        Log.gesture.info("posted key \(key.rawValue, privacy: .public) flags \(flags.rawValue, privacy: .public)")
    }
}
