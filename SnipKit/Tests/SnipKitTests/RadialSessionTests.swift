// ABOUTME: Tests for RadialSession pointer-vector → wedge geometry.
// ABOUTME: Covers dead zone, cardinal directions, and boundary hysteresis.
import XCTest
@testable import SnipKit

final class RadialSessionTests: XCTestCase {
    private func session() -> RadialSession {
        RadialSession(wedgeCount: 8, deadZoneRadius: 24, hysteresisDegrees: 6)
    }

    func testInsideDeadZoneIsNone() {
        XCTAssertEqual(session().selection(dx: 5, dy: -5, previous: .none), .none)
    }

    func testStraightUpIsWedgeZero() {
        XCTAssertEqual(session().selection(dx: 0, dy: -100, previous: .none), .wedge(0))
    }

    func testStraightRightIsWedgeTwo() {   // 90° clockwise from up, 8 wedges → index 2
        XCTAssertEqual(session().selection(dx: 100, dy: 0, previous: .none), .wedge(2))
    }

    func testStraightDownIsWedgeFour() {
        XCTAssertEqual(session().selection(dx: 0, dy: 100, previous: .none), .wedge(4))
    }

    func testHysteresisHoldsPreviousWedgeNearBoundary() {
        let s = session()
        let boundary = 22.5 * Double.pi / 180            // boundary between wedges 0 and 1
        let angle = boundary + (1.0 * Double.pi / 180)   // 1° into wedge 1 territory
        let dx = 100 * sin(angle), dy = -100 * cos(angle)
        XCTAssertEqual(s.selection(dx: dx, dy: dy, previous: .wedge(0)), .wedge(0))
        // With no previous, the same point resolves to wedge 1.
        XCTAssertEqual(s.selection(dx: dx, dy: dy, previous: .none), .wedge(1))
    }
}
