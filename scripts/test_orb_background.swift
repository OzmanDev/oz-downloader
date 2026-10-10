import AppKit
import SwiftUI

@MainActor
final class ScreenModel: ObservableObject {
    var clicks = 0
}

struct ScreenProbe: View {
    @ObservedObject var model: ScreenModel

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.clicks += 1 }
            OrbBackgroundView()
        }
    }
}

@main
enum TestOrbBackground {
    static func main() {
        var failures: [String] = []
        let width: CGFloat = 1000
        let height: CGFloat = 700
        let model = ScreenModel()
        let host = NSHostingView(rootView: ScreenProbe(model: model))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let center = NSPoint(x: width / 2, y: height / 2)
        click(center, on: host, window: window)
        if model.clicks != 1 {
            failures.append("1. a click on the screen should pass through the orb background, got \(model.clicks)")
        }

        let time = Date().timeIntervalSinceReferenceDate
        let orbs = OrbField.orbs(at: time, width: Double(width), height: Double(height))
        for (index, orb) in orbs.enumerated() {
            guard let point = appKitPoint(for: orb, width: width, height: height) else { continue }
            let before = model.clicks
            click(point, on: host, window: window)
            if model.clicks != before + 1 {
                failures.append("2. a click on the \(orb.hue) orb should pass through, got \(model.clicks) after \(before) at orb \(index)")
            }
        }

        window.close()
        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }

    static func click(_ local: NSPoint, on host: NSView, window: NSWindow) {
        let point = host.convert(local, to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
        }
        NSApp.sendEvent(event(.leftMouseDown))
        NSApp.sendEvent(event(.leftMouseUp))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    /// SwiftUI places orbs from the top. AppKit clicks are measured from the bottom.
    static func appKitPoint(for orb: OrbPlacement, width: CGFloat, height: CGFloat) -> NSPoint? {
        let radius: CGFloat = 210
        let clampedX = min(max(CGFloat(orb.x), 0), width)
        let clampedY = min(max(CGFloat(orb.y), 0), height)
        let dx = clampedX - CGFloat(orb.x)
        let dy = clampedY - CGFloat(orb.y)
        guard dx * dx + dy * dy <= radius * radius else { return nil }
        return NSPoint(x: clampedX, y: height - clampedY)
    }
}
