import Carbon.HIToolbox
import Foundation
import TextCorrectCore

/// Registers global (system-wide) hotkeys via Carbon. Used from the main thread.
final class HotkeyManager {
    private static let signature: OSType = 0x5458_434F // 'TXCO'

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var releases: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?
    private var combinations: Set<KeyCombination> = []
    private var nextID: UInt32 = 1

    @discardableResult
    func register(_ combo: KeyCombination, action: @escaping () -> Void, onRelease: (() -> Void)? = nil) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        combinations.insert(combo)
        refs[id] = ref
        actions[id] = action
        releases[id] = onRelease
        return true
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        combinations.removeAll()
        refs.removeAll()
        actions.removeAll()
        releases.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    /// Probes a new system combination without replacing an active registration.
    func isAvailable(_ combo: KeyCombination) -> Bool {
        if combinations.contains(combo) { return true }
        let probe = HotkeyManager()
        let available = probe.register(combo) {}
        probe.unregisterAll()
        return available
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased)),
        ]
        let handler: EventHandlerUPP = { _, event, userData in
            HotkeyManager.dispatch(event: event, userData: userData)
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            2,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private static func dispatch(event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
        guard let event, let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
            manager.releases[hotKeyID.id]?()
        } else { manager.actions[hotKeyID.id]?() }
        return noErr
    }

    private func carbonModifiers(_ modifiers: Set<KeyCombination.Modifier>) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift)   { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option)  { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}
