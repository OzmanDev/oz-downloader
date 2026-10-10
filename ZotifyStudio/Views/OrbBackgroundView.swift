import SwiftUI

struct OrbBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pick = OrbField.openingPick()
    @State private var slid = false
    @State private var started = false
    @State private var generation = 0
    @State private var canvas = CGSize(width: 1000, height: 700)

    var body: some View {
        GeometryReader { proxy in
            let drifts = OrbField.drifts(
                width: proxy.size.width,
                height: proxy.size.height,
                pick: pick
            )
            ZStack {
                ForEach(drifts, id: \.hue) { drift in
                    DriftingOrb(drift: drift, slid: slid)
                }
            }
            .onAppear {
                canvas = proxy.size
                guard !started else { return }
                started = true
                begin(drifts)
            }
            .onChange(of: proxy.size) { newSize in
                canvas = newSize
            }
            .onDisappear {
                generation += 1
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func begin(_ drifts: [OrbDrift]) {
        guard !reduceMotion else { return }
        let seconds = drifts.first?.seconds ?? 3.5
        withAnimation(.easeInOut(duration: seconds)) {
            slid = true
        }
        schedule(after: seconds)
    }

    private func schedule(after seconds: TimeInterval) {
        let ticket = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard ticket == generation else { return }
            advance()
        }
    }

    private func advance() {
        guard !reduceMotion else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pick += 1
            slid = false
        }
        let next = OrbField.drifts(width: canvas.width, height: canvas.height, pick: pick)
        let seconds = next.first?.seconds ?? 3.5
        DispatchQueue.main.async {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: seconds)) {
                slid = true
            }
            schedule(after: seconds)
        }
    }
}

private struct DriftingOrb: View {
    let drift: OrbDrift
    var slid: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color(for: drift.hue))
            .frame(width: 420, height: 420)
            .blur(radius: 70)
            .opacity(0.28)
            .position(x: drift.startX, y: drift.startY)
            .offset(slide)
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
