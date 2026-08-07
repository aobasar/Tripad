import AppKit

@MainActor
protocol MenuBarDelegate: AnyObject {
    var isEnabled: Bool { get set }
    var isAccessibilityTrusted: Bool { get }
    func requestAccessibility()
}

/// The status item and its menu. The menu is also the app's documentation:
/// the gesture map sits in it as disabled rows.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private weak var delegate: MenuBarDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let enabledItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(delegate: MenuBarDelegate) {
        self.delegate = delegate
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "hand.point.up.left",
            accessibilityDescription: "Tripad"
        )
        statusItem.button?.toolTip = "Tripad"

        buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu() {
        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Gestures", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for row in GestureAction.helpRows {
            let item = NSMenuItem(title: "   \(row.gesture)  —  \(row.action)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        accessibilityItem.target = self
        accessibilityItem.action = #selector(handleAccessibility)
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Tripad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Permission can be granted while the app is running, so the state is read
    /// fresh every time the menu opens rather than cached at launch.
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func refresh() {
        guard let delegate else { return }

        enabledItem.state = delegate.isEnabled ? .on : .off

        if delegate.isAccessibilityTrusted {
            accessibilityItem.title = "Accessibility access granted"
            accessibilityItem.isEnabled = false
            accessibilityItem.action = nil
        } else {
            accessibilityItem.title = "⚠︎ Needs Accessibility access — open settings"
            accessibilityItem.isEnabled = true
            accessibilityItem.action = #selector(handleAccessibility)
        }

        statusItem.button?.appearsDisabled = !(delegate.isEnabled && delegate.isAccessibilityTrusted)
    }

    @objc private func toggleEnabled() {
        guard let delegate else { return }
        delegate.isEnabled.toggle()
        refresh()
    }

    @objc private func handleAccessibility() {
        delegate?.requestAccessibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
