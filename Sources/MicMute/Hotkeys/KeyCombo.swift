import Foundation
import AppKit
import Carbon

public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt

    public init(keyCode: UInt32, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        let relevant = modifierFlags.intersection([.command, .option, .control, .shift])
        self.modifiers = UInt(relevant.rawValue)
    }

    /// Default hotkey: Command + \ (kVK_ANSI_Backslash = 42 / 0x2A)
    public static let `default` = KeyCombo(
        keyCode: 42,
        modifierFlags: [.command]
    )

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    }

    public var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    public var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifierFlags.contains(.command) { flags.insert(.maskCommand) }
        if modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
        if modifierFlags.contains(.control) { flags.insert(.maskControl) }
        if modifierFlags.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    public var displayString: String {
        var symbols = ""
        if modifierFlags.contains(.control) { symbols += "⌃" }
        if modifierFlags.contains(.option) { symbols += "⌥" }
        if modifierFlags.contains(.shift) { symbols += "⇧" }
        if modifierFlags.contains(.command) { symbols += "⌘" }

        let keyName = KeyCombo.stringForKeyCode(UInt16(keyCode))
        return symbols + keyName
    }

    public static func stringForKeyCode(_ code: UInt16) -> String {
        switch code {
        case 36: return "⏎"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 117: return "⌦"
        case 126: return "↑"
        case 125: return "↓"
        case 123: return "←"
        case 124: return "→"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: break
        }

        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key(\(code))"
        }

        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var actualLength: Int = 0
        var unicodeString = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            keyLayout,
            code,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &actualLength,
            &unicodeString
        )

        if status == noErr && actualLength > 0 {
            return String(utf16CodeUnits: unicodeString, count: actualLength).uppercased()
        }

        return "Key(\(code))"
    }
}
