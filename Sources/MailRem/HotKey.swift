import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut that can be switched on and off.
final class HotKey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    fileprivate let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyCallback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }

    var isRegistered: Bool { hotKeyRef != nil }

    func register() {
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: OSType(0x4D52_454D), id: 1) // 'MREM'
        RegisterEventHotKey(keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }
}

private func hotKeyCallback(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return noErr }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { hotKey.action() }
    return noErr
}
