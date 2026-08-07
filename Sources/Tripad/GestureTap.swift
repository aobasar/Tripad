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

    /// How far the finger group must travel, in units of trackpad width,
    /// before a swipe counts. Tune here.
    private static let threshold: CGFloat = 0.08

    /// A silence longer than this ends whatever gesture was in progress.
    private static let gestureGap: TimeInterval = 0.4

    /// Touch identities are opaque objects; this makes them dictionary keys.
    private struct TouchKey: Hashable {
        let identity: NSObject
        static func == (lhs: TouchKey, rhs: TouchKey) -> Bool { lhs.identity.isEqual(rhs.identity) }
        func hash(into hasher: inout Hasher) { hasher.combine(identity.hash) }
    }

    private let onSwipe: (SwipeDirection, CGEventFlags) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var startPositions: [TouchKey: CGPoint] = [:]
    /// Set when a swipe fires, cleared when the fingers leave the trackpad:
    /// one gesture is exactly one action, holding still does not repeat it.
    private var locked = false

    /// Diagnostics. Touch counts change rarely enough to log unthrottled, and
    /// they are the only way to see why a swipe did not register.
    private var sawFirstEvent = false
    private var lastLoggedTouchCount = -1
    private var lastEventTimestamp: TimeInterval = 0

    /// When false the tap stays installed but does nothing, so toggling the app
    /// off and on again does not need the permission dance.
    var isEnabled = true

    var isRunning: Bool { tap != nil }

    init(onSwipe: @escaping (SwipeDirection, CGEventFlags) -> Void) {
        self.onSwipe = onSwipe
    }

    /// Modifiers actually held right now, straight from the keyboard state.
    ///
    /// Read live rather than from the gesture event: an event rebuilt with
    /// `NSEvent(cgEvent:)` reports no modifiers, which silently broke the
    /// `⌘`- and `⌃`-qualified gestures. This is also the same source
    /// `KeyPoster` merges into the keys it sends, so the two always agree.
    private var heldModifiers: CGEventFlags {
        CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskControl, .maskShift, .maskAlternate])
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

        if !sawFirstEvent {
            sawFirstEvent = true
            Log.gesture.info("first tapped event, type \(type.rawValue, privacy: .public)")
        }

        guard isEnabled else { return passthrough }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            Log.gesture.info("NSEvent(cgEvent:) returned nil for type \(type.rawValue, privacy: .public)")
            return passthrough
        }
        guard nsEvent.type == .gesture else { return passthrough }

        process(nsEvent)
        return passthrough
    }

    /// height / width of the trackpad, from the device itself. Falls back to a
    /// typical MacBook trackpad if the event does not report a size.
    private func aspectRatio(of touches: Set<NSTouch>) -> CGFloat {
        guard let size = touches.first?.deviceSize, size.width > 0, size.height > 0 else {
            return 0.62
        }
        return size.height / size.width
    }

    private func process(_ event: NSEvent) {
        // Gesture events without any touch payload are interleaved with the
        // real ones. Treating those as "fingers lifted" would reset tracking
        // every other event and no swipe would ever reach the threshold.
        guard !event.touches(matching: .any, in: nil).isEmpty else { return }

        // If the stream goes quiet — the app switcher, say, swallows the events
        // that would have told us the fingers came off — the lock must not stay
        // stuck on. A gap this long is a new gesture by definition.
        if event.timestamp - lastEventTimestamp > Self.gestureGap {
            startPositions.removeAll()
            locked = false
        }
        lastEventTimestamp = event.timestamp

        let touches = event.touches(matching: .touching, in: nil)

        if touches.count != lastLoggedTouchCount {
            lastLoggedTouchCount = touches.count
            Log.gesture.debug("touching contacts: \(touches.count, privacy: .public)")
        }

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
            Log.gesture.debug("tracking 3 contacts, modifiers \(self.heldModifiers.rawValue, privacy: .public)")
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

        // normalizedPosition runs 0...1 on both axes, but the trackpad is much
        // wider than it is tall, so a given physical movement produces a bigger
        // dy than dx. Comparing them raw makes every diagonal read as vertical.
        // Rescaling dy by the aspect ratio puts both in units of trackpad width.
        dy *= aspectRatio(of: touches)

        guard max(abs(dx), abs(dy)) >= Self.threshold else { return }

        // normalizedPosition is bottom-left origin, so positive dy is upward.
        let direction: SwipeDirection = abs(dx) > abs(dy)
            ? (dx > 0 ? .right : .left)
            : (dy > 0 ? .up : .down)

        locked = true
        let modifiers = heldModifiers
        Log.gesture.info("""
            swipe \(String(describing: direction), privacy: .public) \
            dx \(dx, format: .fixed(precision: 3), privacy: .public) \
            dy \(dy, format: .fixed(precision: 3), privacy: .public) \
            modifiers \(modifiers.rawValue, privacy: .public)
            """)
        onSwipe(direction, modifiers)
    }
}
