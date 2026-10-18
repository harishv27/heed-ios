// Generates Heed/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
// Run from the Heed folder:  swift Tools/make-icon.swift
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// Background: indigo, lighter at the top left. iOS rounds the corners itself, so fill the whole square.
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.45, green: 0.42, blue: 0.97, alpha: 1),
    CGColor(red: 0.27, green: 0.24, blue: 0.74, alpha: 1),
] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// A soft highlight band across the top.
let glow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0),
] as CFArray, locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 980), startRadius: 0,
                      endCenter: CGPoint(x: 300, y: 980), endRadius: 700, options: [])

// The check mark: one confident stroke with round ends and a soft shadow.
let check = CGMutablePath()
check.move(to: CGPoint(x: 292, y: 520))
check.addLine(to: CGPoint(x: 452, y: 360))
check.addLine(to: CGPoint(x: 748, y: 690))
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: CGColor(red: 0.1, green: 0.08, blue: 0.4, alpha: 0.45))
cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
cg.setLineWidth(132)
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.addPath(check)
cg.strokePath()
cg.restoreGState()

// The "heed" dot: an amber notification badge at the top right of the check.
let dot = CGRect(x: 702, y: 726, width: 150, height: 150)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(red: 0.3, green: 0.1, blue: 0, alpha: 0.4))
cg.setFillColor(CGColor(red: 1.0, green: 0.72, blue: 0.2, alpha: 1))
cg.fillEllipse(in: dot)
cg.restoreGState()
cg.setStrokeColor(CGColor(red: 0.30, green: 0.27, blue: 0.80, alpha: 1))
cg.setLineWidth(14)
cg.strokeEllipse(in: dot.insetBy(dx: -7, dy: -7))

let png = rep.representation(using: .png, properties: [:])!
let url = URL(fileURLWithPath: "Heed/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try png.write(to: url)
print("wrote \(url.path)")
