import AppKit

let canvas: CGFloat = 1024
let blue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
let violet = NSColor(srgbRed: 0.46, green: 0.32, blue: 0.68, alpha: 1)
let teal = NSColor(srgbRed: 0.18, green: 0.48, blue: 0.50, alpha: 1)
let ink = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { rect in
    NSGraphicsContext.current?.imageInterpolation = .high
    let plate = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 224, yRadius: 224)
    ink.setFill()
    plate.fill()

    NSGraphicsContext.current?.saveGraphicsState()
    plate.addClip()

    let glow: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
        (blue, 220, 780, 340),
        (violet, 860, 180, 380),
        (teal, 140, 260, 300),
    ]
    for (color, cx, cy, radius) in glow {
        let center = NSPoint(x: cx, y: cy)
        NSGradient(colors: [
            color.withAlphaComponent(0.42),
            color.withAlphaComponent(0.0),
        ])?.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    let font = NSFont.systemFont(ofSize: 390, weight: .black)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(string: "OZ", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .kern: -18,
    ])
    let textSize = title.size()
    let textRect = NSRect(
        x: (canvas - textSize.width) / 2,
        y: 168,
        width: textSize.width,
        height: textSize.height
    )
    title.draw(in: textRect)

    let arrow = NSBezierPath()
    let mid = canvas / 2
    arrow.move(to: NSPoint(x: mid - 34, y: 628))
    arrow.line(to: NSPoint(x: mid + 34, y: 628))
    arrow.line(to: NSPoint(x: mid, y: 686))
    arrow.close()
    blue.setFill()
    arrow.fill()
    let shaft = NSBezierPath(
        roundedRect: NSRect(x: mid - 11, y: 572, width: 22, height: 64),
        xRadius: 10,
        yRadius: 10
    )
    shaft.fill()

    let bars: [(CGFloat, NSColor)] = [
        (72, blue),
        (124, teal),
        (176, violet),
        (124, teal),
        (72, blue),
    ]
    let barWidth: CGFloat = 42
    let gap: CGFloat = 20
    let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    var x = (canvas - total) / 2
    let base: CGFloat = 760
    for (height, color) in bars {
        let bar = NSBezierPath(
            roundedRect: NSRect(x: x, y: base, width: barWidth, height: height),
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )
        color.setFill()
        bar.fill()
        x += barWidth + gap
    }

    NSGraphicsContext.current?.restoreGraphicsState()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("could not encode icon\n", stderr)
    exit(1)
}
let out = URL(fileURLWithPath: "ZotifyStudio/Resources/AppIcon.iconset/icon_1024x1024.png")
try png.write(to: out)
print(out.path)
