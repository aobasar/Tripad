import AppKit

enum SwipeDirection {
    case left, right, up, down
}

/// Listens to trackpad gesture events and reports three-finger swipes.
///
/// Detection goes through the public `CGEventTap` + `NSEvent.touches` API, not
/// the private MultitouchSupport.framework: we tap `NSEventTypeGesture`,
/// rebuild an `NSEvent`, and read the touching contacts.
final class GestureTap {

    /// NSEventTypeGesture. It has no `CGEventType` case, so the mask is built
    /// from the raw value.
    private static let gestureEventMask: CGEventMask = 1 << 29

    /// How far the finger group must travel, in normalized trackpad units
    /// (0...1 across the whole surface), before a swipe counts. Tune here.
    private static let threshold: CGFloat = 0.08

    /// Touch identities are opaque objects; this makes them dictionary keys.
    private struct TouchKey: Hashable {
        let identity: NSObject
        static func == (lhs: TouchKey, rhs: TouchKey) -> Bool { lhs.identity.isEqual(rhs.identity) }
        func hash(into hasher: inout Hasher) { hasher.combine(identity.hash) }
    }

    private let onSwipe: (SwipeDirection, NSEvent.ModifierFlags) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var startPositions: [TouchKey: CGPoint] = [:]
    /// Set when a swipe fires, cleared when the fingers leave the trackpad:
    /// one gesture is exactly one action, holding still does not repeat it.
    private var locked = false

    /// When false the tap stays installed but does nothing, so toggling the app
    /// off and on again does not need the permission dance.
    var isEnabled = true

    var isRunning: Bool { tap != nil }

    init(onSwipe: @escaping (SwipeDirection, NSEvent.ModifierFlags) -> Void) {
        self.onSwipe = onSwipe
    }

    /// Installs the tap. Fails (returns false) without Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<GestureTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.gestureEventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        // The system disables a tap that is too slow or when the user takes
        // over the input; both are recoverable by just switching it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passthrough
        }

        guard isEnabled,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .gesture
        else { return passthrough }

        process(nsEvent)
        return passthrough
    }

    private func process(_ event: NSEvent) {
        let touches = event.touches(matching: .touching, in: nil)

        guard touches.count == 3 else {
            startPositions.removeAll()
            locked = false
            return
        }
        guard !locked else { return }

        var current: [TouchKey: CGPoint] = [:]
        for touch in touches {
            guard let identity = touch.identity as? NSObject else { continue }
            current[TouchKey(identity: identity)] = touch.normalizedPosition
        }
        guard current.count == 3 else { return }

        // A different set of fingers means a new gesture: restart from here.
        guard startPositions.count == 3,
              current.keys.allSatisfy({ startPositions[$0] != nil })
        else {
            startPositions = current
            return
        }

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for (key, position) in current {
            guard let start = startPositions[key] else { return }
            dx += position.x - start.x
            dy += position.y - start.y
        }
        dx /= CGFloat(current.count)
        dy /= CGFloat(current.count)

        guard max(abs(dx), abs(dy)) >= Self.threshold else { return }

        // normalizedPosition is bottom-left origin, so positive dy is upward.
        let direction: SwipeDirection = abs(dx) > abs(dy)
            ? (dx > 0 ? .right : .left)
            : (dy > 0 ? .up : .down)

        locked = true
        onSwipe(direction, event.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }
}
