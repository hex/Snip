// ABOUTME: Converts a captured NSEvent (key chord or mouse-button press) into a TriggerBinding plus
// ABOUTME: its human label. Shared by the global trigger recorder and the per-app rule recorder.
import AppKit
import CoreGraphics
import SnipKit

enum TriggerCapture {
    /// The hold binding and label for a captured press: a key chord or a mouse button.
    static func holdBinding(from event: NSEvent) -> (binding: TriggerBinding, label: String)? {
        switch event.type {
        case .keyDown:
            let modifiers = cgEventFlags(from: event.modifierFlags)
            let binding = TriggerBinding.holdKey(code: Int(event.keyCode),
                                                 modifierRawValue: modifiers.rawValue)
            let label = modifierSymbols(for: modifiers)
                + keyLabel(for: event.keyCode, characters: event.charactersIgnoringModifiers)
            return (binding, label)
        case .otherMouseDown:
            return (.holdMouseButton(event.buttonNumber), mouseButtonLabel(for: event.buttonNumber))
        default:
            return nil
        }
    }

    static func mouseButtonLabel(for button: Int) -> String {
        switch button {
        case 2: return "Middle Button"
        default: return "Button \(button + 1)"   // buttonNumber is 0-indexed; people count from 1
        }
    }

    static func modifierSymbols(for flags: CGEventFlags) -> String {
        var symbols = ""
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    static func keyLabel(for keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return characters?.uppercased() ?? "Key \(keyCode)"
        }
    }

    static func cgEventFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}
