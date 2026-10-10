import AppKit
import SwiftUI

/// The What's new sheet sits on the orb background. Its plate is system
/// material, so a color behind the sheet tints the plate.
struct GlassPlateProbe: View {
    var body: some View {
        ZStack {
            Color.red
            WhatsNewSheet(onContinue: {})
        }
        .frame(width: 520, height: 280)
    }
}

@main
enum TestMacGlassPlates {
    static func main() {
        let width: CGFloat = 520
        let height: CGFloat = 280
        let host = NSHostingView(rootView: GlassPlateProbe())
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .aqua)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let end = Date().addingTimeInterval(0.35)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            window.displayIfNeeded()
        }

        // Left padding of the 420-wide sheet, clear of the title text.
        let sample = NSPoint(x: 58, y: height / 2)
        guard let color = pixel(at: sample, in: host) else {
            print("1. could not read the What's new plate")
            exit(1)
        }

        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        // An opaque control fill hides the red backdrop. Material lets it through.
        if red < green + 0.08 || red < blue + 0.08 {
            print("1. the What's new plate should let the backdrop show through, got r=\(red) g=\(green) b=\(blue)")
            window.close()
            exit(1)
        }

        window.close()
    }

    static func pixel(at point: NSPoint, in view: NSView) -> NSColor? {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let scale = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) / bounds.width : 1
        let x = Int(point.x * scale)
        let y = Int((bounds.height - point.y) * scale)
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }
}
