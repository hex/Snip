// ABOUTME: Pure conversions between Quartz (top-left) event coords and Cocoa (bottom-left) window coords.
// ABOUTME: Also clamps the ring's origin so the whole overlay stays on-screen (notch/menu-bar safe).
import CoreGraphics

public enum ScreenGeometry {
    public static func cocoaPoint(fromQuartz p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryScreenHeight - p.y)
    }

    public static func clampedOrigin(forRingSize size: CGFloat, center: CGPoint, in visibleFrame: CGRect) -> CGPoint {
        var x = center.x - size / 2
        var y = center.y - size / 2
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size)
        return CGPoint(x: x, y: y)
    }
}
