// ABOUTME: User-configurable settings for how the radial menu is opened.
// ABOUTME: Middle-mouse hold is the v1 hero trigger; a keyboard chord fallback lands later.
import Foundation

struct TriggerConfig: Codable, Equatable {
    var middleMouseEnabled: Bool = true
}
