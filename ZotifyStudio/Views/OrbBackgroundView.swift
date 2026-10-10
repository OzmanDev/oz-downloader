import SwiftUI

struct OrbBackgroundView: View {
    var body: some View {
        GeometryReader { proxy in
            let drifts = OrbField.drifts(
                width: proxy.size.width,
                height: proxy.size.height
            )
            ZStack {
                ForEach(drifts, id: \.hue) { drift in
                    DriftingOrb(drift: drift)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct DriftingOrb: View {
    let drift: OrbDrift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var slid = false

    var body: some View {
        Circle()
            .fill(color(for: drift.hue))
            .frame(width: 420, height: 420)
            .blur(radius: 70)
            .opacity(0.28)
            .position(x: drift.startX, y: drift.startY)
            .offset(slide)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: drift.seconds).repeatForever(autoreverses: true)) {
                    slid = true
                }
            }
    }

    private var slide: CGSize {
        guard !reduceMotion, slid else { return .zero }
        return CGSize(
            width: drift.endX - drift.startX,
            height: drift.endY - drift.startY
        )
    }

    private func color(for hue: String) -> Color {
        switch hue {
        case "blue":
            return Color.accentColor
        case "violet":
            return Color(red: 0.46, green: 0.32, blue: 0.68)
        case "teal":
            return Color(red: 0.18, green: 0.48, blue: 0.50)
        default:
            return Color.clear
        }
    }
}
