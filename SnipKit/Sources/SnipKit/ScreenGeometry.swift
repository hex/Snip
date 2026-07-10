// ABOUTME: Pure conversions between Quartz (top-left) event coords and Cocoa (bottom-left) window coords.
// ABOUTME: Also places the overlay canvas, which is always centered on the cursor, never clamped.
import CoreGraphics

public enum ScreenGeometry {
    public static func cocoaPoint(fromQuartz p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryScreenHeight - p.y)
    }

    /// The bottom-left origin of a `size` x `size` canvas centered on `center`.
    ///
    /// Deliberately unclamped. The wedge is chosen from the press anchor, so nudging the ring
    /// back on screen would make the drawing and the geometry disagree: the user would drag
    /// toward the wedge they can see and a different one would fire.
    public static func centeredOrigin(forSize size: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x - size / 2, y: center.y - size / 2)
    }
}
