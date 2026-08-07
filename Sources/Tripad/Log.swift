import OSLog

/// Read the app's own account of what happened with:
///   log show --last 5m --predicate 'subsystem == "com.aobasar.Tripad"' --info
///
/// Worth having in a permission-gated, invisible menu-bar app: without it the
/// only symptom of a missing grant or a swallowed gesture is nothing at all
/// happening.
enum Log {
    static let app = Logger(subsystem: "com.aobasar.Tripad", category: "app")
    static let gesture = Logger(subsystem: "com.aobasar.Tripad", category: "gesture")
}
