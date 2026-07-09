// ABOUTME: SwiftUI radial (pie) menu — render only, zero input handling (display-only invariant).
// ABOUTME: Frosted ring with hairline spokes, an accent highlight wedge, labels, and a bloom spring.
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
    private let hubFraction: CGFloat = 0.30
    private let labelRadius: CGFloat = 80
    private let accent = Color(red: 1.0, green: 0.48, blue: 0.40)

    var body: some View {
        ZStack {
            VisualEffectView(diameter: Self.ringSize)

            // Gives the ring its own ground so contrast never depends on what's behind the window.
            Circle().fill(.black.opacity(0.34))

            if case let .wedge(i) = model.selection {
                WedgeShape(index: i, wedgeCount: 8, innerRadiusFraction: hubFraction)
                    .fill(accent.opacity(0.45))
            }

            SpokesShape(wedgeCount: 8, innerRadiusFraction: hubFraction)
                .stroke(.white.opacity(0.14), lineWidth: 1)

            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)

            ForEach(0..<8, id: \.self) { index in
                wedgeLabel(index)
            }

            Circle()
                .fill(.white.opacity(0.07))
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .frame(width: Self.ringSize * hubFraction, height: Self.ringSize * hubFraction)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        // No SwiftUI .shadow(): it rasterizes the hosted NSVisualEffectView as a rectangle.
        // The panel draws a circular shadow from the masked content's alpha instead.
        .scaleEffect(model.isVisible ? 1.0 : 0.86)
        .opacity(model.isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: model.isVisible)
    }

    @ViewBuilder private func wedgeLabel(_ index: Int) -> some View {
        let angle = Double(index) * .pi / 4          // clockwise from up
        let isSelected = model.selection == .wedge(index)
        let label = model.labels[index]

        // The accent lives on the wedge fill; the selected label goes white so it stays legible on it.
        Text(label ?? "+")
            .font(.system(size: 12, weight: label == nil ? .regular : .semibold))
            .foregroundStyle(labelColor(isSelected: isSelected, isEmpty: label == nil))
            .scaleEffect(isSelected ? 1.12 : 1.0)
            .offset(x: labelRadius * sin(angle), y: -labelRadius * cos(angle))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private func labelColor(isSelected: Bool, isEmpty: Bool) -> Color {
        if isSelected { return .white }
        if isEmpty { return .white.opacity(0.32) }
        return .white.opacity(0.92)
    }
}
