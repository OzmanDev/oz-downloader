import AppKit
import SwiftUI

@main
enum TestOrbMotion {
    static func main() {
        let width: CGFloat = 1000
        let height: CGFloat = 700
        let host = NSHostingView(rootView: OrbBackgroundView())
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: height))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        pump(0.6, window: window)

        guard let first = capture(host) else {
            print("1. could not capture the first orb background bitmap")
            exit(1)
        }
        if first.allSatisfy({ $0 == 0 }) {
            print("1. the first orb background bitmap is blank, so a frame did not paint")
            exit(1)
        }

        pump(2.0, window: window)

        guard let second = capture(host) else {
            print("1. could not capture the second orb background bitmap")
            exit(1)
        }

        if first == second {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            print("1. orb background pixels should change after about 2 seconds, but the bitmaps match (reduce motion \(reduceMotion))")
            exit(1)
        }

        window.close()
    }

    static func pump(_ seconds: TimeInterval, window: NSWindow) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            window.displayIfNeeded()
        }
    }

    static func capture(_ view: NSView) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 10, bounds.height > 10 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        guard let raw = rep.bitmapData else { return nil }
        let byteCount = rep.bytesPerRow * rep.pixelsHigh
        guard byteCount > 0 else { return nil }
        return Data(bytes: raw, count: byteCount)
    }
}
