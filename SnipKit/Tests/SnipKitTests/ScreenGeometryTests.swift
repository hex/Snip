// ABOUTME: Tests for ScreenGeometry Quartz to Cocoa conversion and overlay placement.
// ABOUTME: Guards the multi-display Y-flip and the rule that the ring stays centered on the cursor.
import XCTest
@testable import SnipKit

final class ScreenGeometryTests: XCTestCase {
    func testQuartzTopLeftMapsToCocoaBottomLeft() {
        // Quartz (0,0) is top-left; on an 1080-tall primary screen it becomes Cocoa (0,1080).
        let point = ScreenGeometry.cocoaPoint(fromQuartz: CGPoint(x: 0, y: 0), primaryScreenHeight: 1080)
        XCTAssertEqual(point, CGPoint(x: 0, y: 1080))
    }

    func testQuartzMidPointFlips() {
        let point = ScreenGeometry.cocoaPoint(fromQuartz: CGPoint(x: 300, y: 200), primaryScreenHeight: 1080)
        XCTAssertEqual(point, CGPoint(x: 300, y: 880))
    }

    func testOriginCentersTheCanvasOnThePoint() {
        let origin = ScreenGeometry.centeredOrigin(forSize: 320, center: CGPoint(x: 500, y: 400))
        XCTAssertEqual(origin, CGPoint(x: 340, y: 240))
    }

    /// The wedge is chosen from the press anchor, so the ring must never slide away from the
    /// cursor to fit on screen: the drawing and the geometry would then disagree.
    func testOriginIsNotClampedToTheScreenNearAnEdge() {
        let origin = ScreenGeometry.centeredOrigin(forSize: 320, center: CGPoint(x: 10, y: 12))
        XCTAssertEqual(origin, CGPoint(x: -150, y: -148))
    }
}
