// ABOUTME: Pure geometry mapping a pointer vector (from the bloom anchor) to a wedge selection.
// ABOUTME: Wedge 0 points up; indices increase clockwise; a center dead zone yields .none.
import Foundation

public enum RadialSelection: Equatable {
    case none
    case wedge(Int)
}

public struct RadialSession {
    private let wedgeCount: Int
    private let deadZoneRadius: Double
    private let hysteresisRadians: Double

    public init(wedgeCount: Int, deadZoneRadius: Double, hysteresisDegrees: Double) {
        self.wedgeCount = wedgeCount
        self.deadZoneRadius = deadZoneRadius
        self.hysteresisRadians = hysteresisDegrees * .pi / 180
    }

    public func selection(dx: Double, dy: Double, previous: RadialSelection) -> RadialSelection {
        if (dx * dx + dy * dy).squareRoot() < deadZoneRadius { return .none }

        let wedgeAngle = 2 * Double.pi / Double(wedgeCount)
        // Angle clockwise from straight up. dy is downward, so up is -dy.
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }

        let raw = Int((angle / wedgeAngle).rounded()) % wedgeCount

        // Hysteresis: keep the previous wedge unless we've moved past its boundary + margin.
        if case let .wedge(prev) = previous, prev != raw {
            let prevCenter = Double(prev) * wedgeAngle
            var delta = abs(angle - prevCenter)
            if delta > .pi { delta = 2 * .pi - delta }
            if delta < wedgeAngle / 2 + hysteresisRadians { return .wedge(prev) }
        }
        return .wedge(raw)
    }
}
