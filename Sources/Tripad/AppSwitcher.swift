import AppKit

/// Steps through the running apps directly, without the `⌘Tab` overlay.
///
/// `⌘Tab` cannot do this: the switcher panel is the shortcut, and it stays up
/// as long as `⌘` is held. Since the point of the gesture is to change app
/// immediately, Tripad activates the next app itself.
///
/// The order is deliberately stable — the apps sorted by process id, which is
/// launch order — rather than most-recently-used. Without a panel to look at,
/// an MRU cycle has no visible state and just bounces between the last two
/// apps; a fixed ring means repeated swipes walk the whole list and come back
/// round, which is what makes "keep swiping to get there" work.
@MainActor
enum AppSwitcher {

    static func step(_ offset: Int) {
        let apps = switchable()
        guard apps.count > 1 else { return }

        // Fall back to the start of the ring if the frontmost app is not in the
        // list (it may have no Dock icon, like a full-screen system panel).
        let currentIndex = apps.firstIndex { $0.isActive } ?? 0
        let target = apps[(currentIndex + offset + apps.count) % apps.count]

        Log.gesture.info("""
            activating \(target.localizedName ?? "?", privacy: .public) \
            (\(currentIndex + 1, privacy: .public) -> \
            \(apps.firstIndex(of: target).map { $0 + 1 } ?? 0, privacy: .public) \
            of \(apps.count, privacy: .public))
            """)

        target.activate(options: [.activateAllWindows])
    }

    /// Apps a person would consider "open": a Dock icon, not hidden, not us.
    private static func switchable() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { $0.processIdentifier < $1.processIdentifier }
    }
}
