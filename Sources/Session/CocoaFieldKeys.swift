import AppKit

/// macOS text-field shortcuts → readline/zsh bytes.
enum CocoaFieldKeys {
    private static let left: UInt16 = 123
    private static let right: UInt16 = 124
    private static let backspace: UInt16 = 51
    private static let forwardDelete: UInt16 = 117

    static func bytes(flags: NSEvent.ModifierFlags, keyCode: UInt16) -> [UInt8]? {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if mods.contains(.shift) || mods.contains(.control) {
            return nil
        }
        let command = mods.contains(.command)
        let option = mods.contains(.option)

        if command, !option {
            switch keyCode {
            case left: return [0x01] // beginning of line (Ctrl+A)
            case right: return [0x05] // end of line (Ctrl+E)
            case backspace: return [0x15] // delete to start of line (Ctrl+U)
            case forwardDelete: return [0x0b] // delete to end of line (Ctrl+K)
            default: return nil
            }
        }

        if option, !command {
            switch keyCode {
            case left: return [0x1b, 0x62] // back word (Esc+b)
            case right: return [0x1b, 0x66] // forward word (Esc+f)
            case backspace: return [0x17] // delete word (Ctrl+W)
            case forwardDelete: return [0x1b, 0x64] // delete word forward (Esc+d)
            default: return nil
            }
        }

        return nil
    }
}
