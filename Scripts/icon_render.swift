#!/usr/bin/env swift
// Renders the HubOS app icon to a 1024×1024 PNG using Core Graphics.
// Usage: swift icon_render.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

// Squircle geometry — macOS icon grid keeps ~100px transparent padding.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius = rect.width * 0.2237
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow beneath the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18),
              blur: 55,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Brand gradient fill (indigo → violet → pink), clipped to the squircle.
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let indigo = NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 1).cgColor
let violet = NSColor(red: 0.63, green: 0.35, blue: 0.98, alpha: 1).cgColor
let pink   = NSColor(red: 0.98, green: 0.36, blue: 0.68, alpha: 1).cgColor
let grad = CGGradient(colorsSpace: cs, colors: [indigo, violet, pink] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY),
                       options: [])

// Glossy top highlight for the liquid-glass sheen.
let gloss = CGGradient(colorsSpace: cs,
                       colors: [NSColor.white.withAlphaComponent(0.38).cgColor,
                                NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(gloss,
                       start: CGPoint(x: rect.midX, y: rect.maxY),
                       end: CGPoint(x: rect.midX, y: rect.midY + 40),
                       options: [])
ctx.restoreGState()

// Inner top stroke to sharpen the glass edge.
ctx.saveGState()
ctx.addPath(path)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// White stacked-layers glyph, centered.
let cfg = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
if let base = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let sz = base.size
    let tinted = NSImage(size: sz)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: sz)
    base.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let drawRect = NSRect(x: (S - sz.width) / 2,
                          y: (S - sz.height) / 2 - 8,
                          width: sz.width, height: sz.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6),
                  blur: 24,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    tinted.draw(in: drawRect)
    ctx.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("✓ Rendered \(outPath)")
