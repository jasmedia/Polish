// Draws the app icon and writes App/Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// A speech bubble with a check mark and a sparkle on a blue squircle, on the macOS icon grid
// (824 pt body on a 1024 pt canvas). Rerun after changing the drawing; the .icns is committed.
import AppKit

let canvas: CGFloat = 1024

func draw(in context: CGContext) {
    // Body: continuous-corner squircle with a top-to-bottom gradient and a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).cgPath
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(squircle)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let colors = [NSColor(srgbRed: 0.33, green: 0.62, blue: 1.0, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.24, green: 0.33, blue: 0.93, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // Speech bubble with a tail at the bottom left.
    let bubble = CGMutablePath()
    bubble.addPath(NSBezierPath(roundedRect: CGRect(x: 232, y: 330, width: 560, height: 400), xRadius: 120, yRadius: 120).cgPath)
    bubble.move(to: CGPoint(x: 330, y: 360))
    bubble.addLine(to: CGPoint(x: 282, y: 236))
    bubble.addQuadCurve(to: CGPoint(x: 470, y: 340), control: CGPoint(x: 400, y: 280))
    bubble.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    context.addPath(bubble)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // Check mark in the body's blue.
    let check = CGMutablePath()
    check.move(to: CGPoint(x: 382, y: 532))
    check.addLine(to: CGPoint(x: 470, y: 446))
    check.addLine(to: CGPoint(x: 646, y: 620))
    context.addPath(check)
    context.setStrokeColor(NSColor(srgbRed: 0.27, green: 0.45, blue: 0.97, alpha: 1).cgColor)
    context.setLineWidth(58)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    // Sparkle at the top right: a four-point star.
    func sparkle(center: CGPoint, radius: CGFloat) {
        let star = CGMutablePath()
        let waist = radius * 0.22
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let next = angle + .pi / 4
            let side = CGPoint(x: center.x + cos(next) * waist, y: center.y + sin(next) * waist)
            i == 0 ? star.move(to: tip) : star.addLine(to: tip)
            star.addLine(to: side)
        }
        star.closeSubpath()
        context.addPath(star)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
    }
    sparkle(center: CGPoint(x: 790, y: 790), radius: 76)
    sparkle(center: CGPoint(x: 694, y: 862), radius: 30)
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let out = "App/Resources/AppIcon.icns"
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try png(size: 1024).write(to: URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory() + "AppIcon.png"))
print("Wrote \(out)")
