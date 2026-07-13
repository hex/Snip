// ABOUTME: The user's single trigger for opening the ring: a held key chord, a held mouse button,
// ABOUTME: or a double-click-and-hold of a mouse button. Pure matching logic; no event tap here.
import CoreGraphics
import Foundation

/// How the ring is opened. A key chord and a mouse button are both "hold" gestures; a mouse button
/// can also be armed by a double-click whose second press is then held. Modelling the three cases
/// as one enum makes the illegal combination "double-click a keyboard key" unrepresentable.
public enum TriggerBinding: Codable, Equatable {
    case holdKey(code: Int, modifierRawValue: UInt64)
    case holdMouseButton(Int)
    case doubleClickMouseButton(Int)

    /// Does a mouse-button press open the ring? A hold opens on any press of its button; a
    /// double-click opens only once the window server reports the click is the 2nd (or later) in a
    /// series, so the first single click passes through to the app underneath.
    public func mouseDownOpens(button: Int64, clickState: Int64) -> Bool {
        switch self {
        case .holdMouseButton(let n):
            return button == Int64(n)
        case .doubleClickMouseButton(let n):
            return button == Int64(n) && clickState >= 2
        case .holdKey:
            return false
        }
    }

    /// The modifier bits we compare; caps-lock, fn, and numeric-pad bits are ignored so they can't
    /// silently block a match.
    private static let watchedModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    /// Does a key press open the ring? The keycode must match and the watched modifiers must match
    /// exactly, so ⌘⌥Space never fires an ⌥Space binding.
    public func keyOpens(code: Int64, flags: CGEventFlags) -> Bool {
        guard case let .holdKey(c, raw) = self, code == Int64(c) else { return false }
        let watched = Self.watchedModifiers
        return flags.intersection(watched) == CGEventFlags(rawValue: raw).intersection(watched)
    }

    /// Is this the bound key's keycode, regardless of modifiers? Used to swallow autorepeats and to
    /// commit on key-up, where the user may have released the modifier while still holding the key.
    public func isKeyCode(_ code: Int64) -> Bool {
        guard case let .holdKey(c, _) = self else { return false }
        return code == Int64(c)
    }

    /// Is this the bound mouse button? Used to track drag and commit on release once the ring is open,
    /// where the double-click gate no longer applies.
    public func isMouseButton(_ button: Int64) -> Bool {
        guard let n = mouseButtonNumber else { return false }
        return button == Int64(n)
    }

    /// The bound keycode, for polling `keyState` in the watchdog. Nil for mouse bindings.
    public var keyCode: Int? {
        guard case let .holdKey(c, _) = self else { return nil }
        return c
    }

    /// The bound mouse-button number, for polling `buttonState` in the watchdog. Nil for a key binding.
    public var mouseButtonNumber: Int? {
        switch self {
        case .holdMouseButton(let n), .doubleClickMouseButton(let n): return n
        case .holdKey: return nil
        }
    }
}

/// The user's single trigger plus a human label for it (e.g. "Middle Button", "⌥Space"). The label
/// is display-only; matching runs off `binding`.
public struct TriggerConfig: Codable, Equatable {
    public var binding: TriggerBinding
    public var label: String

    public init(binding: TriggerBinding = .holdMouseButton(2), label: String = "Middle Button") {
        self.binding = binding
        self.label = label
    }
}
