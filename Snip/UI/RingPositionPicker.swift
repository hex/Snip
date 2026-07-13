// ABOUTME: A miniature ring that picks a snippet's bearing by its shape instead of a dropdown label.
// ABOUTME: Tap a nub to pin to that position; tap the lit nub again to unpin. nil == Unpinned.
import SwiftUI

struct RingPositionPicker: View {
    @Binding var slot: Int?
    var size: CGFloat = 100

    var body: some View {
        let center = size / 2
        let radius = size / 2 - 13
        ZStack {
            Circle()
                .stroke(HUD.hairline, lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
                .position(x: center, y: center)

            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi   // 0 at top, clockwise
                nub(i)
                    .position(x: center + radius * sin(angle),
                              y: center - radius * cos(angle))
            }

            Text(slot.map { RingEditorView.slotNames[$0] } ?? "Unpinned")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(slot == nil ? HUD.textMuted : HUD.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: radius * 1.3)
                .position(x: center, y: center)
        }
        .frame(width: size, height: size)
    }

    private func nub(_ i: Int) -> some View {
        let active = slot == i
        return Circle()
            .fill(active ? HUD.signal : HUD.chamber)
            .frame(width: 15, height: 15)
            .overlay(Circle().strokeBorder(active ? Color.clear : HUD.hairline, lineWidth: 1))
            .shadow(color: active ? HUD.signal.opacity(0.6) : .clear, radius: active ? 6 : 0)
            .contentShape(Circle().inset(by: -7))   // a forgiving tap target
            .onTapGesture { slot = active ? nil : i }
    }
}
