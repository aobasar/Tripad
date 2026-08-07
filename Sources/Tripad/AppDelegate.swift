import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarDelegate {

    private var gestureTap: GestureTap?
    private var menuBar: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("launched, accessibility trusted: \(Accessibility.isTrusted, privacy: .public)")

        let tap = GestureTap { direction, modifiers in
            GestureAction.perform(direction, modifiers: modifiers)
        }
        tap.isEnabled = Settings.isEnabled
        gestureTap = tap

        menuBar = MenuBarController(delegate: self)

        if !startTapIfPossible() {
            Accessibility.requestPrompt()
            waitForPermission()
        }
        menuBar?.refresh()
    }

    /// Returns true once the tap is installed.
    @discardableResult
    private func startTapIfPossible() -> Bool {
        guard let gestureTap else { return false }
        if gestureTap.isRunning { return true }
        guard Accessibility.isTrusted else { return false }
        let started = gestureTap.start()
        Log.app.info("event tap start: \(started ? "ok" : "failed", privacy: .public)")
        return started
    }

    /// Permission is granted outside the app, so poll instead of asking the
    /// user to relaunch.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.startTapIfPossible() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.menuBar?.refresh()
            }
        }
    }

    // MARK: - MenuBarDelegate

    var isEnabled: Bool {
        get { Settings.isEnabled }
        set {
            Settings.isEnabled = newValue
            gestureTap?.isEnabled = newValue
        }
    }

    var isAccessibilityTrusted: Bool { Accessibility.isTrusted }

    func requestAccessibility() {
        Accessibility.requestPrompt()
        Accessibility.openSettings()
        waitForPermission()
    }
}
