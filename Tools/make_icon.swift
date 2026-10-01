import AppKit

// Renders AppIcon.iconset PNGs: a white clock-face chat bubble reading 9:30 on a blurple squircle.
// Usage: swift make_icon.swift <output.iconset>

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Point on a circle, measured clockwise from 12 o'clock (AppKit's y axis points up).
func onDial(_ center: CGPoint, _ radius: CGFloat, degrees: CGFloat) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(x: center.x + radius * sin(radians), y: center.y + radius * cos(radians))
}

func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Squircle on the macOS icon grid: 824pt body centered in 1024pt.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: rgb(0x000000, 0.30))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(0x5865F2))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [rgb(0x8A93FF), rgb(0x5865F2), rgb(0x3C3FB8)] as CFArray,
                                locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
    ctx.restoreGState()

    // Clock-face bubble with a tail toward the lower left.
    let center = CGPoint(x: 524, y: 536)
    let radius: CGFloat = 290
    let bubble = CGMutablePath()
    bubble.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    let tail = CGMutablePath()
    let tailStart = onDial(center, radius - 30, degrees: 205)
    let tailEnd = onDial(center, radius - 30, degrees: 238)
    let tip = CGPoint(x: 252, y: 236)
    tail.move(to: tailStart)
    tail.addQuadCurve(to: tip, control: CGPoint(x: 318, y: 300))
    tail.addQuadCurve(to: tailEnd, control: CGPoint(x: 330, y: 300))
    tail.closeSubpath()
    let shape = bubble.union(tail)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x14164A, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.addPath(shape)
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Gentle top-to-bottom shading on the face.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let face = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xE9EBF5)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: 512, y: center.y + radius), end: CGPoint(x: 512, y: 200), options: [])
    ctx.restoreGState()

    // Tick marks.
    ctx.setLineCap(.round)
    for hour in 0..<12 {
        let major = hour % 3 == 0
        ctx.setStrokeColor(rgb(0x2B2D42, major ? 0.9 : 0.35))
        ctx.setLineWidth(major ? 16 : 10)
        let angle = CGFloat(hour) * 30
        ctx.move(to: onDial(center, radius - 34, degrees: angle))
        ctx.addLine(to: onDial(center, radius - (major ? 78 : 62), degrees: angle))
        ctx.strokePath()
    }

    // Hands at 9:30, with a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: rgb(0x000000, 0.25))
    ctx.setStrokeColor(rgb(0x1E1F2E))
    ctx.setLineWidth(30)
    ctx.move(to: onDial(center, 22, degrees: 105))
    ctx.addLine(to: onDial(center, 150, degrees: 285))
    ctx.strokePath()
    ctx.setLineWidth(22)
    ctx.move(to: onDial(center, 26, degrees: 0))
    ctx.addLine(to: onDial(center, 238, degrees: 180))
    ctx.strokePath()
    ctx.restoreGState()

    // Blurple second hand and hub.
    ctx.setStrokeColor(rgb(0x5865F2))
    ctx.setLineWidth(9)
    ctx.move(to: onDial(center, 54, degrees: 230))
    ctx.addLine(to: onDial(center, 236, degrees: 50))
    ctx.strokePath()
    ctx.setFillColor(rgb(0x5865F2))
    ctx.fillEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let file = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try render(pixels: points * scale).write(to: file)
    }
}
