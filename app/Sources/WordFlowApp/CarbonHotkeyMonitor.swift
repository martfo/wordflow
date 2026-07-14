// The § hotkey via Carbon's RegisterEventHotKey — a system hotkey dispatched by
// the window server, not an event tap. Unlike a CGEventTap it fires even when
// another app has macOS secure input on (a password box, or an app that leaves
// secure input stuck), which is why a tap-based hotkey silently stops working
// and this one keeps going. It also needs no Accessibility permission.
//
// Registering the key claims it globally while active (so § is swallowed and
// never types), and gives key-down (pressed) and key-up (released) events for
// hold-to-talk. Esc is registered only while recording, so it cancels then and
// types normally otherwise. Modifier-only hotkeys (Right ⌘, fn) cannot be Carbon
// hotkeys; those fall back to reporting unavailable.

import AppKit
import Carbon
import WordFlowCore

@MainActor
final class CarbonHotkeyMonitor {
    var onEvent: ((HotkeyEvent) -> Void)?
    private(set) var kind: HotkeyKind = .section

    private var hotKeyRef: EventHotKeyRef?
    private var escRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature = OSType(0x57464C57)  // 'WFLW'
    private let mainID: UInt32 = 1
    private let escID: UInt32 = 2

    func setHotkey(_ kind: HotkeyKind) {
        self.kind = kind
        if hotKeyRef != nil { _ = enable() }
    }

    @discardableResult
    func enable() -> Bool {
        installHandler()
        unregisterMain()
        guard !kind.isModifierKey else {
            wfLog("Carbon hotkey: \(kind.rawValue) is modifier-only, not supported")
            return false
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: mainID)
        let status = RegisterEventHotKey(
            UInt32(kind.keyCode), 0, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
            wfLog("Carbon hotkey registered: keyCode=\(kind.keyCode) status=\(status)")
            return true
        }
        wfLog("Carbon hotkey registration FAILED: keyCode=\(kind.keyCode) status=\(status)")
        return false
    }

    func disable() {
        unregisterMain()
        endEscCapture()
    }

    /// Claim Esc only while recording, so it cancels then and is untouched
    /// otherwise.
    func beginEscCapture() {
        guard escRef == nil else { return }
        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: escID)
        if RegisterEventHotKey(0x35, 0, id, GetApplicationEventTarget(), 0, &ref) == noErr {
            escRef = ref
        }
    }

    func endEscCapture() {
        if let escRef {
            UnregisterEventHotKey(escRef)
            self.escRef = nil
        }
    }

    private func unregisterMain() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased)),
        ]
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, refcon in
                guard let event, let refcon else { return noErr }
                let monitor = Unmanaged<CarbonHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(event)
            },
            2, &types, refcon, &handlerRef)
    }

    private nonisolated func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        let eventKind = GetEventKind(event)
        let isEsc = hotKeyID.id == escID
        return MainActor.assumeIsolated {
            wfLog("Carbon event: id=\(hotKeyID.id) kind=\(eventKind)")
            if isEsc {
                if eventKind == UInt32(kEventHotKeyPressed) { onEvent?(.escape) }
            } else if eventKind == UInt32(kEventHotKeyPressed) {
                onEvent?(.keyDown)
            } else if eventKind == UInt32(kEventHotKeyReleased) {
                onEvent?(.keyUp)
            }
            return noErr
        }
    }
}
