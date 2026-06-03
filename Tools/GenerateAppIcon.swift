#!/usr/bin/env swift
//
// GenerateAppIcon.swift — renders the MacDring app icon at every macOS size.
//
// A gradient squircle (the "screen") with three colored tabs riding on the right
// edge — the signature color-per-tab edge tabs — the middle one opened into a
// white drawer of app icons.
//
// Usage:
//   swift Tools/GenerateAppIcon.swift <output-appiconset-dir>
// Defaults to the in-repo AppIcon.appiconset if no path is given.

import AppKit
import Foundation

let defaultOut = "MacDring/Resources/Assets.xcassets/AppIcon.appiconset"
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOut

/// (pixel size, filename) for every slot in the macOS app-icon set.
let files: [(px: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a).cgColor
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A rectangle with only its left (leading) corners rounded — the right side
/// stays square so the tab reads as flush against the screen's right edge.
func roundedLeftRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let r = min(radius, rect.height / 2)
    let p = CGMutablePath()
    let tl = CGPoint(x: rect.minX, y: rect.maxY)
    let tr = CGPoint(x: rect.maxX, y: rect.maxY)
    let br = CGPoint(x: rect.maxX, y: rect.minY)
    let bl = CGPoint(x: rect.minX, y: rect.minY)
    p.move(to: tr)
    p.addLine(to: br)
    p.addArc(tangent1End: bl, tangent2End: tl, radius: r)
    p.addArc(tangent1End: tl, tangent2End: tr, radius: r)
    p.closeSubpath()
    return p
}

func drawIcon(px: Int) -> NSBitmapImageRep {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    let ctx = nsctx.cgContext

    // Squircle "screen"
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = roundedRect(rect, rect.width * 0.2237)

    // Soft drop shadow under the squircle.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.28))
    ctx.addPath(squircle); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()

    // Brand gradient fill (blue → indigo, top to bottom).
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgb(92, 152, 255), rgb(54, 64, 198)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY),
                           options: [])
    ctx.restoreGState()

    func frac(_ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat) -> CGRect {
        CGRect(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height,
               width: fw * rect.width, height: fh * rect.height)
    }

    // Keep everything inside the rounded "screen".
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()

    // Drawer panel (white), pulled out from the middle (open) tab.
    let drawerRect = frac(0.15, 0.34, 0.47, 0.32)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: s * 0.004, height: -s * 0.006), blur: s * 0.022, color: rgb(0, 0, 0, 0.22))
    ctx.addPath(roundedRect(drawerRect, drawerRect.height * 0.16))
    ctx.setFillColor(rgb(255, 255, 255, 0.98)); ctx.fillPath()
    ctx.restoreGState()

    // A 2×2 grid of app icons inside the drawer (only legible at larger sizes).
    if px >= 64 {
        let dotColors = [rgb(255, 159, 10), rgb(48, 209, 88), rgb(10, 132, 255), rgb(255, 69, 58)]
        let pad = drawerRect.width * 0.15
        let cellW = (drawerRect.width - pad * 2) / 2
        let cellH = (drawerRect.height - pad * 2) / 2
        let dot = min(cellW, cellH) * 0.66
        var i = 0
        for row in 0..<2 {
            for col in 0..<2 {
                let cx = drawerRect.minX + pad + (CGFloat(col) + 0.5) * cellW
                let cy = drawerRect.minY + pad + (CGFloat(row) + 0.5) * cellH
                let r = CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot)
                ctx.addPath(roundedRect(r, dot * 0.28)); ctx.setFillColor(dotColors[i % 4]); ctx.fillPath()
                i += 1
            }
        }
    }

    // Three colored tabs riding flush on the right edge — the color-per-tab
    // signature. The middle one is "open" and overlaps the drawer; the others
    // sit closed. Each is rounded on its inward (left) side only, square on the
    // right so it reads as flush against the screen edge (the rounded screen
    // corner clips the top/bottom tabs).
    let tabSpecs: [(fy: CGFloat, fw: CGFloat, color: CGColor)] = [
        (0.655, 0.36, rgb(48, 209, 88)),    // green  (top, closed)
        (0.415, 0.43, rgb(255, 159, 10)),   // orange (middle, open — reaches the drawer)
        (0.175, 0.36, rgb(10, 210, 225)),   // cyan   (bottom, closed)
    ]
    for spec in tabSpecs {
        // Flush to the screen's right edge (rect.maxX); the squircle clip trims
        // the top/bottom tabs to the rounded corner.
        let tabRect = frac(1.0 - spec.fw, spec.fy, spec.fw, 0.17)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -s * 0.004, height: 0), blur: s * 0.016, color: rgb(0, 0, 0, 0.22))
        ctx.addPath(roundedLeftRect(tabRect, tabRect.height * 0.42))
        ctx.setFillColor(spec.color); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.restoreGState()   // unclip
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

for file in files {
    let rep = drawIcon(px: file.px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(file.name)\n".utf8))
        continue
    }
    do {
        try data.write(to: outURL.appendingPathComponent(file.name))
        print("wrote \(file.name) (\(file.px)px)")
    } catch {
        FileHandle.standardError.write(Data("failed to write \(file.name): \(error)\n".utf8))
    }
}
