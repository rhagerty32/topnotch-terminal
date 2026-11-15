import Carbon
import Foundation

/// One process-wide summon shortcut. Carbon hot keys work while another app is active.
@MainActor
final class SummonHotkey {
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x544E_5448 // 'TNTH'

    func apply(_ choice: SummonHotkeyChoice) {
        unregister()
        guard let spec = Self.spec(for: choice) else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let target = GetApplicationEventTarget()
        let status = InstallEventHandler(
            target,
            Self.callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            NSLog("Summon hotkey handler failed: \(status)")
            return
        }
        let register = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            EventHotKeyID(signature: signature, id: 1),
            target,
            0,
            &hotKey
        )
        if register != noErr {
            NSLog("Summon hotkey \(choice.title) is unavailable: \(register)")
            unregister()
        }
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private static let callback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == 0x544E_5448 else { return noErr }
        let hotkey = Unmanaged<SummonHotkey>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                hotkey.onPress?()
            }
        }
        return noErr
    }

    private static func spec(for choice: SummonHotkeyChoice) -> (keyCode: UInt32, modifiers: UInt32)? {
        let command = UInt32(cmdKey)
        let shift = UInt32(shiftKey)
        let option = UInt32(optionKey)
        let control = UInt32(controlKey)
        switch choice {
        case .none:
            return nil
        case .controlOptionT:
            return (UInt32(kVK_ANSI_T), control | option)
        case .optionSpace:
            return (UInt32(kVK_Space), option)
        case .commandShiftSpace:
            return (UInt32(kVK_Space), command | shift)
        }
    }
}
