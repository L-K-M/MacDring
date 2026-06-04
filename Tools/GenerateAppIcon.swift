#!/usr/bin/env swift
//
// GenerateAppIcon.swift — renders the MacDring app icon at every macOS size.
//
// A gradient squircle (the "screen") with a single rounded drawer pulled up from
// its bottom edge — the signature edge drawer, rendered as one clean white panel.
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

/// A rectangle with independently-rounded top and bottom corners — lets the
/// drawer carry a generous top radius while keeping its base tucked tight.
func roundedRect(_ rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let t = min(top, rect.width / 2, rect.height / 2)
    let b = min(bottom, rect.width / 2, rect.height / 2)
    let tl = CGPoint(x: rect.minX, y: rect.maxY)
    let tr = CGPoint(x: rect.maxX, y: rect.maxY)
    let br = CGPoint(x: rect.maxX, y: rect.minY)
    let bl = CGPoint(x: rect.minX, y: rect.minY)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY + b))
    p.addArc(tangent1End: tl, tangent2End: tr, radius: t)  // top-left
    p.addArc(tangent1End: tr, tangent2End: br, radius: t)  // top-right
    p.addArc(tangent1End: br, tangent2End: bl, radius: b)  // bottom-right
    p.addArc(tangent1End: bl, tangent2End: tl, radius: b)  // bottom-left
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

    // Keep the drawer inside the rounded "screen".
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()

    // A single rounded drawer pulled up from the screen's bottom edge — the
    // signature edge drawer. Generous top corners, a tighter base, tucked close
    // to the bottom so it reads as riding that edge.
    let drawerRect = frac(0.20, 0.085, 0.60, 0.45)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.03, color: rgb(0, 0, 0, 0.28))
    ctx.addPath(roundedRect(drawerRect, top: drawerRect.width * 0.20, bottom: drawerRect.width * 0.11))
    ctx.setFillColor(rgb(255, 255, 255, 0.97)); ctx.fillPath()
    ctx.restoreGState()

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
