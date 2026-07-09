// ABOUTME: Tests for ScreenGeometry Quartz↔Cocoa conversion and ring clamping.
// ABOUTME: Guards the multi-display Y-flip and on-screen clamping (notch/menu-bar safe).
import XCTest
@testable import SnipKit

final class ScreenGeometryTests: XCTestCase {
    func testQuartzTopLeftMapsToCocoaBottomLeft() {
        // Quartz (0,0) is top-left; on an 1080-tall primary screen it becomes Cocoa (0,1080).
        let p = ScreenGeometry.cocoaPoint(fromQuartz: CGPoint(x: 0, y: 0), primaryScreenHeight: 1080)
        XCTAssertEqual(p, CGPoint(x: 0, y: 1080))
    }

    func testQuartzMidPointFlips() {
        let p = ScreenGeometry.cocoaPoint(fromQuartz: CGPoint(x: 300, y: 200), primaryScreenHeight: 1080)
        XCTAssertEqual(p, CGPoint(x: 300, y: 880))
    }

    func testRingClampsInsideVisibleFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        // Ring size 200 centered at the corner must not spill past the edges.
        let origin = ScreenGeometry.clampedOrigin(forRingSize: 200, center: CGPoint(x: 0, y: 0), in: frame)
        XCTAssertEqual(origin, CGPoint(x: 0, y: 0))
    }

    func testRingCentersWhenRoomAllows() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let origin = ScreenGeometry.clampedOrigin(forRingSize: 200, center: CGPoint(x: 500, y: 500), in: frame)
        XCTAssertEqual(origin, CGPoint(x: 400, y: 400))
    }
}
