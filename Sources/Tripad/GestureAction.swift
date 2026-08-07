import AppKit

enum GestureAction {

    /// The gesture map as the menu shows it. The menu doubles as the help
    /// document, so this table and `perform` are meant to be read side by side
    /// and changed together.
    static let helpRows: [(gesture: String, action: String)] = [
        ("3 fingers ← / →", "Switch tabs"),
        ("3 fingers ↑ / ↓", "Switch windows"),
        ("⌘ + 3 fingers ← / →", "Switch apps"),
        ("⌃ + 3 fingers ← / →", "Switch desktops (follows fingers)"),
        ("⌥ + 3 fingers ← / →", "Move window to next desktop"),
    ]

    /// The modifier held during a gesture is the modifier of the shortcut it
    /// fires, which is why the held key is never synthesized here. App
    /// switching is the exception: it does not post `⌘Tab` at all, because the
    /// switcher panel is inseparable from that shortcut. See `AppSwitcher`.
    @MainActor
    static func perform(_ direction: SwipeDirection, modifiers: CGEventFlags) {
        if modifiers.contains(.maskCommand) {
            switch direction {
            case .left: AppSwitcher.step(-1)
            case .right: AppSwitcher.step(1)
            case .up, .down: break
            }
            return
        }

        if modifiers.contains(.maskControl) {
            // Inverted on purpose: the desktop follows the fingers, the way
            // natural scrolling moves the page rather than the viewport. Swipe
            // left and the next desktop comes in from the right.
            switch direction {
            case .left: KeyPoster.post(.rightArrow)  // ⌃→
            case .right: KeyPoster.post(.leftArrow)  // ⌃←
            case .up, .down: break
            }
            return
        }

        // Same inversion as switching desktops: the window goes the way the
        // desktop would have gone.
        if modifiers.contains(.maskAlternate) {
            switch direction {
            case .left: WindowMover.move(1)
            case .right: WindowMover.move(-1)
            case .up, .down: break
            }
            return
        }

        switch direction {
        case .left: KeyPoster.post(.tab, adding: [.maskControl, .maskShift])  // ⌃⇧Tab
        case .right: KeyPoster.post(.tab, adding: .maskControl)               // ⌃Tab
        case .up: KeyPoster.post(.grave, adding: [.maskCommand, .maskShift])  // ⌘⇧`
        case .down: KeyPoster.post(.grave, adding: .maskCommand)              // ⌘`
        }
    }
}
