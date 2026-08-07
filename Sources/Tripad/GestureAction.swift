import AppKit

enum GestureAction {

    /// The gesture map as the menu shows it. The menu doubles as the help
    /// document, so this table and `perform` are meant to be read side by side
    /// and changed together.
    static let helpRows: [(gesture: String, action: String)] = [
        ("3 fingers ← / →", "Switch tabs"),
        ("3 fingers ↑ / ↓", "Switch windows"),
        ("⌘ + 3 fingers ← / →", "Switch apps"),
        ("⌃ + 3 fingers ← / →", "Switch desktops"),
    ]

    /// The modifier held during a gesture is the modifier of the shortcut it
    /// fires, which is why the held key is never synthesized here.
    static func perform(_ direction: SwipeDirection, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            switch direction {
            case .left: KeyPoster.post(.tab, adding: .maskShift)  // ⌘⇧Tab
            case .right: KeyPoster.post(.tab)                     // ⌘Tab
            case .up, .down: break
            }
            return
        }

        if modifiers.contains(.control) {
            switch direction {
            case .left: KeyPoster.post(.leftArrow)    // ⌃←
            case .right: KeyPoster.post(.rightArrow)  // ⌃→
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
