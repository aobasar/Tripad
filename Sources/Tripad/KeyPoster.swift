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

    /// Posts one key press, by default starting from the modifiers the user is
    /// physically holding and adding `extraFlags` on top.
    ///
    /// The merge is usually the point: the gesture's modifier is the shortcut's
    /// modifier, so we send the bare key and let it combine with what is already
    /// down instead of synthesizing a duplicate.
    ///
    /// Pass `mergingHeld: false` when the held modifier is *not* part of the
    /// shortcut — moving a window is triggered with `⌥` held but has to follow
    /// up with a clean `⌃→`, and a stray `⌥` would turn that into "move by
    /// word" instead of "move a space".
    static func post(
        _ key: KeyCode,
        adding extraFlags: CGEventFlags = [],
        mergingHeld: Bool = true
    ) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let held = mergingHeld
            ? CGEventSource.flagsState(.combinedSessionState).intersection(carriedFlags)
            : []
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
