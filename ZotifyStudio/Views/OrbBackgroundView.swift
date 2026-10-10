import SwiftUI

struct OrbBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let orbs = OrbField.orbs(
                    at: time,
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                ZStack {
                    ForEach(Array(orbs.enumerated()), id: \.offset) { _, orb in
                        Circle()
                            .fill(color(for: orb.hue))
                            .frame(width: 420, height: 420)
                            .blur(radius: 100)
                            .opacity(0.22)
                            .position(x: orb.x, y: orb.y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
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
