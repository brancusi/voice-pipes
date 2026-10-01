import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys through Carbon, which reports both key-down and key-up
/// (needed for press-and-hold triggers) and needs no Accessibility permission.
@MainActor
final class HotkeyManager {
    typealias Handler = (_ pressed: Bool) -> Void

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: Handler] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { manager.handlers[hotKeyID.id]?(pressed) }
            return noErr
        }, specs.count, &specs, selfPtr, &eventHandler)
    }

    /// Replaces all track registrations. Returns combos that could not be registered (taken by another app).
    @discardableResult
    func register(_ bindings: [(KeyCombo, Handler)]) -> [KeyCombo] {
        unregisterAll()
        return bindings.compactMap { combo, handler in add(combo, handler) == nil ? combo : nil }
    }

    /// Registers one hotkey and returns its id, or nil if the combo is unavailable.
    func add(_ combo: KeyCombo, _ handler: @escaping Handler) -> UInt32? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5654_4C53), id: id) // 'VTLS'
        let status = RegisterEventHotKey(combo.key.code, combo.modifiers.carbonFlags, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func remove(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }
}
