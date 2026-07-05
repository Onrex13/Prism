#!/usr/bin/env swift
// Renders the DMG background (1200×800 = 600×400pt @2x) to a PNG.
// Layout matches the icon positions set in make_dmg.sh (app at ~150,220 and
// Applications at ~450,220 in points).
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg_background.png"
let W = 1200.0, H = 800.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

// Background gradient.
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    NSColor(red: 0.07, green: 0.07, blue: 0.13, alpha: 1).cgColor,
    NSColor(red: 0.15, green: 0.10, blue: 0.22, alpha: 1).cgColor,
    NSColor(red: 0.20, green: 0.11, blue: 0.24, alpha: 1).cgColor
] as CFArray, locations: [0, 0.6, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

// Soft brand glow top-center.
let glow = CGGradient(colorsSpace: cs, colors: [
    NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 0.30).cgColor,
    NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 0).cgColor
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W/2, y: H - 150), startRadius: 0,
                       endCenter: CGPoint(x: W/2, y: H - 150), endRadius: 420, options: [])

// Note: Core Graphics origin is bottom-left; text drawn via AppKit which is also
// bottom-left here. Positions below are in the 1200×800 pixel space.
func drawText(_ s: String, x: CGFloat, centerY: CGFloat, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, align: NSTextAlignment = .center) {
    let para = NSMutableParagraphStyle(); para.alignment = align
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: para
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let bounds = str.size()
    let rect = NSRect(x: x - bounds.width/2, y: centerY - bounds.height/2, width: bounds.width, height: bounds.height)
    str.draw(in: rect)
}

// Title + subtitle near the top (pixel y measured from bottom; content ≈ top 372pt of the image is visible).
drawText("HubOS", x: W/2, centerY: H - 90, size: 60, weight: .bold,
         color: NSColor(red: 0.78, green: 0.55, blue: 0.98, alpha: 1))
drawText("Ton Mac, en mieux.", x: W/2, centerY: H - 170, size: 25, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.6))

// Arrow between the two icons (icon row at point y≈185 → pixel y = 800 - 370 = 430).
let arrowY = H - 370
ctx.saveGState()
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
ctx.setLineWidth(6)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 478, y: arrowY))
ctx.addLine(to: CGPoint(x: 722, y: arrowY))
ctx.strokePath()
ctx.move(to: CGPoint(x: 694, y: arrowY + 20))
ctx.addLine(to: CGPoint(x: 726, y: arrowY))
ctx.addLine(to: CGPoint(x: 694, y: arrowY - 20))
ctx.strokePath()
ctx.restoreGState()

// Instruction beneath the icons.
drawText("Glissez HubOS dans le dossier Applications", x: W/2, centerY: H - 660, size: 23,
         weight: .medium, color: NSColor.white.withAlphaComponent(0.75))

NSGraphicsContext.restoreGraphicsState()
// Tag the image as @2x (600×400 points) so Finder sizes the background to the
// window's point dimensions instead of treating pixels as points.
rep.size = NSSize(width: W / 2, height: H / 2)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
