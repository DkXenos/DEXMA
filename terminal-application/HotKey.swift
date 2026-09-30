import Carbon.HIToolbox
import os

/// A system-wide keyboard shortcut via Carbon's `RegisterEventHotKey`, still the only
/// public global-hotkey API that needs no Accessibility or Input Monitoring permission.
final class HotKey {
    private static let signature: OSType = 0x4E54_524D  // 'NTRM'
    private static var nextID: UInt32 = 1
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchTerm",
                                       category: "HotKey")

    private let id: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// False if Carbon refused the combination (e.g. another app holds it exclusively).
    private(set) var isRegistered = false

    /// `keyCode` is a virtual key code (`kVK_…`), `modifiers` Carbon flags (`optionKey`, …).
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler,
                                                1, &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(),
                                                &handlerRef)
        let registerStatus = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                                 EventHotKeyID(signature: Self.signature, id: id),
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = installStatus == noErr && registerStatus == noErr
        if !isRegistered {
            Self.logger.error(
                "Hotkey registration failed: install \(installStatus), register \(registerStatus)")
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Every hotkey handler on the application target sees every hotkey press, so only
    /// claim the ones registered by this instance.
    fileprivate func handle(_ hotKeyID: EventHotKeyID) -> Bool {
        guard hotKeyID.signature == Self.signature, hotKeyID.id == id else { return false }
        action()
        return true
    }
}

/// A C function pointer can't carry actor isolation, hence `nonisolated`. Carbon delivers
/// hotkey events from the main thread's event loop, which makes `assumeIsolated` safe.
private nonisolated func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        hotKey.handle(hotKeyID) ? noErr : OSStatus(eventNotHandledErr)
    }
}
