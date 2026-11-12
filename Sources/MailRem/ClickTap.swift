import AppKit
import CoreGraphics

/// Watches for Option + right-click and hands it to the app instead of the
/// frontmost application. Requires the Accessibility permission.
final class ClickTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate let shouldHandle: () -> Bool
    fileprivate let handler: (CGPoint) -> Void

    /// Returns nil when the tap cannot be created, which happens when the
    /// Accessibility permission has not been granted.
    init?(shouldHandle: @escaping () -> Bool, handler: @escaping (CGPoint) -> Void) {
        self.shouldHandle = shouldHandle
        self.handler = handler

        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: clickTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return nil
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    deinit {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    fileprivate func reenable() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Clicks once at the given point with no modifier keys, so the item under
    /// the pointer becomes the selection.
    static func leftClick(at point: CGPoint) {
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: eventSource, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }
}

private func clickTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)
    guard let userInfo = userInfo else { return passThrough }
    let clickTap = Unmanaged<ClickTap>.fromOpaque(userInfo).takeUnretainedValue()

    // macOS disables a tap that responds too slowly; turn it back on.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        clickTap.reenable()
        return passThrough
    }
    guard type == .rightMouseDown else { return passThrough }

    let modifiers = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
    guard modifiers == .maskAlternate, clickTap.shouldHandle() else { return passThrough }

    let location = event.location
    DispatchQueue.main.async { clickTap.handler(location) }
    return nil // swallow the click so the app's own context menu does not open
}
