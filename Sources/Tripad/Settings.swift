import Foundation

/// The whole persisted state of the app: one on/off flag.
enum Settings {
    private static let enabledKey = "enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}
