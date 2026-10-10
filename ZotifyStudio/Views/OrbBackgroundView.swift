import SwiftUI

struct OrbBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clockStart = Date()

    var body: some View {
        Group {
            if reduceMotion {
                circles(at: clockStart.timeIntervalSinceReferenceDate)
            } else {
                TimelineView(.periodic(from: clockStart, by: 1.0 / 30.0)) { timeline in
                    circles(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func circles(at time: TimeInterval) -> some View {
        GeometryReader { proxy in
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
