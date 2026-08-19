#!/usr/bin/env swift
// Run on the Mac: `swift Scripts/make-icon.swift`
//
// Renders Resources/AppIcon.icns from code rather than from a checked-in
// design file, so the icon can be tweaked by editing numbers and rebuilt
// without any image toolchain. The .icns is committed, so an ordinary build
// never runs this.
//
// Typing + piano: a keycap whose face is a piano keyboard. The motif has to
// survive 32 px, which is why the cap is large, the key count is low, and the
// glow does the colour work rather than fine detail.

import AppKit
import CoreGraphics
import Foundation

// Palette lifted from UI/KeyCapView.swift — the icon and the app should not
// drift apart.
let background = CGColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1)
let backgroundTop = CGColor(red: 0.098, green: 0.113, blue: 0.137, alpha: 1)
let melody = CGColor(red: 0.33, green: 0.73, blue: 1.00, alpha: 1)
let chord = CGColor(red: 1.00, green: 0.69, blue: 0.31, alpha: 1)

/// macOS icons are drawn inside a squircle that leaves a margin on all sides;
/// filling the full canvas makes the icon look oversized next to every other
/// app in the Dock.
let inset: CGFloat = 0.104

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// Apple's continuous-corner squircle, approximated with a rounded rect at the
/// standard 22.37% corner radius.
func squirclePath(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect,
           cornerWidth: rect.width * 0.2237,
           cornerHeight: rect.height * 0.2237,
           transform: nil)
}

func draw(size: Int) -> CGImage {
    let ctx = makeContext(size)
    let s = CGFloat(size)
    let margin = s * inset
    let plate = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)

    // MARK: Squircle body
    ctx.saveGState()
    ctx.addPath(squirclePath(plate))
    ctx.clip()
    let shades = [backgroundTop, background] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: shades, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: plate.maxY),
                           end: CGPoint(x: 0, y: plate.minY),
                           options: [])

    // Two coloured glows rim-lighting the lower corners: melody-blue left,
    // chord-amber right, matching how the app tints its two key zones.
    //
    // Centred *outside* the plate and kept weak on purpose. Centred inside and
    // at full strength they wash across the middle and turn the warm corner to
    // mud, which is exactly what the first draft did.
    for (colour, x) in [(melody, plate.minX - plate.width * 0.10),
                        (chord, plate.maxX + plate.width * 0.10)] {
        let glow = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [colour.copy(alpha: 0.42)!,
                     colour.copy(alpha: 0.10)!,
                     colour.copy(alpha: 0)!] as CFArray,
            locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: x, y: plate.minY + plate.height * 0.12), startRadius: 0,
            endCenter: CGPoint(x: x, y: plate.minY + plate.height * 0.12),
            endRadius: plate.width * 0.60,
            options: [])
    }
    ctx.restoreGState()

    // A hairline rim so the icon reads against a dark Dock.
    ctx.saveGState()
    ctx.addPath(squirclePath(plate))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    // MARK: The keycap
    let capW = plate.width * 0.72
    let capH = capW * 0.82
    let cap = CGRect(x: plate.midX - capW / 2,
                     y: plate.midY - capH / 2 + plate.height * 0.015,
                     width: capW, height: capH)
    let capRadius = capW * 0.13

    ctx.saveGState()
    // Skipped below 64 px: at 32 the blur is wider than the cap's own edge and
    // reads as smudge rather than depth.
    if size >= 64 {
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                      blur: s * 0.05, color: CGColor(gray: 0, alpha: 0.55))
    }
    ctx.addPath(CGPath(roundedRect: cap, cornerWidth: capRadius,
                       cornerHeight: capRadius, transform: nil))
    ctx.setFillColor(CGColor(red: 0.21, green: 0.235, blue: 0.27, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Top-lit bevel: a light band across the upper third sells it as a
    // physical key rather than a flat rectangle.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: cap, cornerWidth: capRadius,
                       cornerHeight: capRadius, transform: nil))
    ctx.clip()
    let bevel = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(bevel,
                           start: CGPoint(x: 0, y: cap.maxY),
                           end: CGPoint(x: 0, y: cap.midY),
                           options: [])
    ctx.restoreGState()

    // A bright hairline along the cap's top edge. This one line is most of what
    // separates "a keycap catching light" from "a grey rounded rectangle".
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: cap.insetBy(dx: s * 0.004, dy: s * 0.004),
                       cornerWidth: capRadius, cornerHeight: capRadius, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, s * 0.005))
    ctx.strokePath()
    ctx.restoreGState()

    // MARK: Piano keys on the cap face
    //
    // Five whites and three blacks — one octave minus a note. Fewer keys than
    // a real octave on purpose: at 32 px, seven whites turn into grey mush.
    let faceInset = capW * 0.10
    let face = cap.insetBy(dx: faceInset, dy: capH * 0.16)
    let whiteCount = 5
    let whiteW = face.width / CGFloat(whiteCount)
    let gap = max(s * 0.0025, whiteW * 0.05)
    let keyRadius = whiteW * 0.14

    for i in 0..<whiteCount {
        let key = CGRect(x: face.minX + CGFloat(i) * whiteW + gap / 2,
                         y: face.minY,
                         width: whiteW - gap,
                         height: face.height)
        ctx.addPath(CGPath(roundedRect: key, cornerWidth: keyRadius,
                           cornerHeight: keyRadius, transform: nil))
        ctx.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        ctx.fillPath()
    }

    // Blacks sit between whites 0-1, 1-2 and 3-4 — the C-D-E / G-A pattern,
    // which is what makes it read as a piano and not as a barcode.
    let blackW = whiteW * 0.56
    let blackH = face.height * 0.60
    for i in [0, 1, 3] {
        let centre = face.minX + CGFloat(i + 1) * whiteW
        let key = CGRect(x: centre - blackW / 2,
                         y: face.maxY - blackH,
                         width: blackW, height: blackH)
        ctx.addPath(CGPath(roundedRect: key, cornerWidth: keyRadius * 0.8,
                           cornerHeight: keyRadius * 0.8, transform: nil))
        ctx.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1))
        ctx.fillPath()
    }

    // MARK: Zone tint
    //
    // The leftmost white glows melody-blue and the rightmost chord-amber: the
    // instrument's actual split, stated in one gesture.
    for (colour, index) in [(melody, 0), (chord, whiteCount - 1)] {
        let key = CGRect(x: face.minX + CGFloat(index) * whiteW + gap / 2,
                         y: face.minY,
                         width: whiteW - gap,
                         height: face.height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: key, cornerWidth: keyRadius,
                           cornerHeight: keyRadius, transform: nil))
        ctx.clip()
        let tint = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [colour.copy(alpha: 0.95)!, colour.copy(alpha: 0.30)!] as CFArray,
            locations: [0, 1])!
        ctx.drawLinearGradient(tint,
                               start: CGPoint(x: 0, y: key.minY),
                               end: CGPoint(x: 0, y: key.maxY),
                               options: [])
        ctx.restoreGState()
    }

    return ctx.makeImage()!
}

// MARK: - Emit

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? ".")
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1)
    }
    try data.write(to: url)
}

// The iconset sizes macOS actually asks for.
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                        (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(points)x\(points)\(suffix).png"
    try write(draw(size: pixels), to: iconset.appendingPathComponent(name))
}

// A standalone 1024 for eyeballing the design without opening the .icns.
try write(draw(size: 1024), to: resources.appendingPathComponent("AppIcon-preview.png"))

// A contact sheet at the sizes the icon is actually seen at. The 1024 render
// always looks fine; 16 and 32 are where a design fails, so they get looked at
// deliberately rather than hoped about.
if CommandLine.arguments.contains("--sheet") {
    let shown = [16, 32, 64, 128, 256]
    let pad = 24
    let width = shown.reduce(0) { $0 + $1 + pad } + pad
    let height = (shown.max() ?? 256) + pad * 2
    let sheet = makeContext(max(width, height))
    sheet.setFillColor(CGColor(gray: 0.5, alpha: 1))
    sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
    var x = pad
    for size in shown {
        // Bottom-aligned on a common baseline so the sizes are comparable.
        sheet.draw(draw(size: size),
                   in: CGRect(x: x, y: pad, width: size, height: size))
        x += size + pad
    }
    try write(sheet.makeImage()!, to: resources.appendingPathComponent("AppIcon-sizes.png"))
    print("wrote Resources/AppIcon-sizes.png")
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path,
                     "-o", resources.appendingPathComponent("AppIcon.icns").path]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
print("wrote Resources/AppIcon.icns + AppIcon-preview.png")
