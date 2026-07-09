// ABOUTME: SwiftUI radial (pie) menu, render only, zero input handling (display-only invariant).
// ABOUTME: A magnifying lens lands first, then the glass ring unfurls around it.
import SwiftUI
import SnipKit

/// An annular sector covering one wedge of the ring.
struct WedgeShape: Shape {
    let index: Int
    let wedgeCount: Int
    let innerRadiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRadiusFraction
        let wedge = 360.0 / Double(wedgeCount)
        let centerAngle = -90.0 + Double(index) * wedge   // wedge 0 points straight up
        let start = Angle(degrees: centerAngle - wedge / 2)
        let end = Angle(degrees: centerAngle + wedge / 2)

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A donut. Filled with `FillStyle(eoFill: true)` so the hub stays a hole.
struct RingShape: Shape {
    let holeFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        let side = rect.width * holeFraction
        path.addEllipse(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                                   width: side, height: side))
        return path
    }
}

/// Hairlines on the boundaries between wedges.
struct SpokesShape: Shape {
    let wedgeCount: Int
    let innerRadiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRadiusFraction
        let wedge = 2 * Double.pi / Double(wedgeCount)

        var path = Path()
        for i in 0..<wedgeCount {
            let angle = -Double.pi / 2 + (Double(i) + 0.5) * wedge   // boundary, not center
            let from = CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle))
            let to = CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle))
            path.move(to: from)
            path.addLine(to: to)
        }
        return path
    }
}

struct RadialMenuView: View {
    var model: RadialViewModel

    static let ringSize: CGFloat = 236
    /// Headroom so the spring's overshoot, the unwinding rotation, and label shadows
    /// are not guillotined by the window bounds.
    static let canvasSize: CGFloat = 320
    /// Hub diameter as a fraction of the ring, and equally the wedge inner-radius fraction.
    static let hubFraction: CGFloat = 0.30

    private var hubSize: CGFloat { Self.ringSize * Self.hubFraction }
    private let labelRadius: CGFloat = 80
    /// The user's System Settings accent. Dynamic, so it resolves against the panel's dark appearance.
    private let accent = Color(nsColor: .controlAccentColor)

    // The lens lands first and the ring unfurls around it, so the eye gets an anchor.
    private let ringDelay = 0.10
    private let labelDelay = 0.17

    private var lensBloom: Animation { .spring(response: 0.30, dampingFraction: 0.60) }
    private var bloom: Animation { .spring(response: 0.34, dampingFraction: 0.62) }
    private var dismiss: Animation { .easeOut(duration: 0.14) }

    /// An exit is not an entrance in reverse: it barely shrinks, and it never un-rotates.
    private var hiddenScale: CGFloat { model.isDismissing ? 0.94 : 0.72 }
    private var hiddenRotation: Double { model.isDismissing ? 0 : -6 }
    private var hiddenLabelScale: CGFloat { model.isDismissing ? 1.0 : 0.55 }
    private var hiddenHubScale: CGFloat { model.isDismissing ? 1.0 : 0.32 }

    var body: some View {
        ZStack {
            Color.clear
            ringGroup
            hubGroup   // a sibling, not a child: a parent's transform would drag it along
        }
        .frame(width: Self.canvasSize, height: Self.canvasSize)
    }

    // MARK: - Ring

    private var ringGroup: some View {
        ZStack {
            // Drop shadow drawn in SwiftUI, so it springs with the ring instead of lagging it.
            // Blurring a plain Shape is safe; blurring the hosted NSVisualEffectView is not.
            RingShape(holeFraction: Self.hubFraction)
                .fill(.black.opacity(0.26), style: FillStyle(eoFill: true))
                .blur(radius: 13)
                .offset(y: 6)

            VisualEffectView(diameter: Self.ringSize, holeFraction: Self.hubFraction)

            // A whisper of tint on the glass only. Labels carry their own contrast via shadow.
            RingShape(holeFraction: Self.hubFraction)
                .fill(.black.opacity(0.16), style: FillStyle(eoFill: true))

            // Specular sheen: light falls from above, like real glass.
            RingShape(holeFraction: Self.hubFraction)
                .fill(LinearGradient(colors: [.white.opacity(0.12), .clear],
                                     startPoint: .top, endPoint: .center),
                      style: FillStyle(eoFill: true))

            if case let .wedge(index) = model.selection {
                WedgeShape(index: index, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .fill(accent.opacity(0.50))
            }

            SpokesShape(wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                .stroke(.white.opacity(0.16), lineWidth: 1)

            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.10)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)

            ForEach(0..<8, id: \.self) { index in
                wedgeLabel(index)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .scaleEffect(model.isVisible ? 1.0 : hiddenScale)
        .rotationEffect(.degrees(model.isVisible ? 0 : hiddenRotation))
        .opacity(model.isVisible ? 1.0 : 0.0)
        .animation(model.isVisible ? bloom.delay(ringDelay) : dismiss, value: model.isVisible)
    }

    // MARK: - Lens

    /// A hole through the glass, magnifying the real pixels behind the window, dressed with the
    /// two opposed cues that read as glass: a shadow on the near inside edge, a specular on the far.
    private var hubGroup: some View {
        ZStack {
            // Past ~0.5 the centre magnifies so hard it samples almost nothing, and a page of
            // text becomes a white bulge. Legibility is the point of a magnifier.
            LensDistortionView(diameter: hubSize, magnification: 0.45)

            Circle().fill(.white.opacity(0.04))

            Circle()
                .stroke(.black.opacity(0.40), lineWidth: 7)
                .blur(radius: 4)
                .offset(y: -4)
                .mask(Circle())

            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 4)
                .blur(radius: 2.5)
                .offset(y: 4)
                .mask(Circle())

            Circle().strokeBorder(.black.opacity(0.24), lineWidth: 1)
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.50), .white.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        }
        .frame(width: hubSize, height: hubSize)
        .scaleEffect(model.isVisible ? 1.0 : hiddenHubScale)
        .opacity(model.isVisible ? 1.0 : 0.0)
        .animation(model.isVisible ? lensBloom : dismiss, value: model.isVisible)
    }

    // MARK: - Labels

    @ViewBuilder private func wedgeLabel(_ index: Int) -> some View {
        let angle = Double(index) * .pi / 4          // clockwise from up
        let isSelected = model.selection == .wedge(index)
        let label = model.labels[index]
        // Petals travel outward as the ring opens, but they do not retract on the way out.
        let radius = labelRadius * (model.isVisible ? 1.0 : hiddenLabelScale)

        Text(label ?? "+")
            .font(.system(size: 12, weight: label == nil ? .regular : .semibold))
            .foregroundStyle(labelColor(isSelected: isSelected, isEmpty: label == nil))
            // The ring is translucent, so type carries its own contrast over any background.
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .scaleEffect(isSelected ? 1.12 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            .offset(x: radius * sin(angle), y: -radius * cos(angle))
            .opacity(model.isVisible ? 1.0 : 0.0)
            .animation(model.isVisible ? bloom.delay(labelDelay + Double(index) * 0.014) : dismiss,
                       value: model.isVisible)
    }

    private func labelColor(isSelected: Bool, isEmpty: Bool) -> Color {
        if isSelected { return .white }
        if isEmpty { return .white.opacity(0.34) }
        return .white.opacity(0.94)
    }
}
