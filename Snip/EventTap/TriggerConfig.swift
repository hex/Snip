// ABOUTME: User-configurable settings for how the radial menu is opened.
// ABOUTME: Supports a middle-mouse hold and a keyboard chord hold, either of which can be disabled.
import CoreGraphics
import Foundation

struct TriggerConfig: Codable, Equatable {
    var middleMouseEnabled: Bool = true

    var hotkeyEnabled: Bool = true
    var hotkeyKeyCode: Int = 49                 // Space
    var hotkeyModifierRawValue: UInt64 = CGEventFlags.maskAlternate.rawValue   // Option
    var hotkeyKeyLabel: String = "Space"

    var hotkeyModifiers: CGEventFlags { CGEventFlags(rawValue: hotkeyModifierRawValue) }
}
