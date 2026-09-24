#!/usr/bin/env swift
// Draws the Oh My Android icons with Core Graphics:
//   - the app icon, every size the asset catalog needs
//   - the menu bar icon, a template image (robot head)
// Usage: Scripts/make-icon.swift [assets-folder]   (default: Sources/App/Assets.xcassets)
//
// Motif: the Android robot caught by surprise: "Oh my!" Wide eyes, open mouth, arms up.
// Layout follows the macOS icon grid: 824 pt body inside a 1024 pt canvas.
// The Android robot is reproduced or modified from work created and shared by Google and used
// according to terms described in the Creative Commons 3.0 Attribution License.
import AppKit
import CoreGraphics

let assets = CommandLine.arguments.dropFirst().first ?? "Sources/App/Assets.xcassets"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
}

/// Straight bar with round ends, drawn as a stroked line.
func capsule(_ context: CGContext, from: CGPoint, to: CGPoint, width: CGFloat) {
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.move(to: from)
    context.addLine(to: to)
    context.strokePath()
}

// MARK: - Robot

/// Robot parts as paths, in icon coordinates (y up). Shared by the app icon and the menu bar icon.
enum Robot {
    static let headCenter = CGPoint(x: 512, y: 520)
    static let headRadius: CGFloat = 250

    static var head: CGPath {
        let path = CGMutablePath()
        path.addArc(center: headCenter, radius: headRadius, startAngle: 0, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        return path
    }

    /// Antennas, spread wide: the robot is startled.
    static let antennas: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 400, y: 730), CGPoint(x: 322, y: 858)),
        (CGPoint(x: 624, y: 730), CGPoint(x: 702, y: 858)),
    ]

    static var body: CGPath {
        CGPath(roundedRect: CGRect(x: 262, y: 40, width: 500, height: 460), cornerWidth: 70, cornerHeight: 70, transform: nil)
    }

    /// Both arms thrown up beside the head.
    static let arms: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 200, y: 440), CGPoint(x: 150, y: 690)),
        (CGPoint(x: 824, y: 440), CGPoint(x: 874, y: 690)),
    ]
}

// MARK: - App icon

func drawAppIcon(size: Int) -> Data {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let frame = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: frame, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow, as on system icons.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x0F2A3F))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // Background: deep teal night with a soft spotlight behind the robot.
    context.drawLinearGradient(gradient([color(0x173B57), color(0x0B1B2B)]),
                               start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.minY), options: [])
    let spot = CGPoint(x: 512, y: 560)
    context.drawRadialGradient(gradient([color(0x3DDC84, 0.35), color(0x3DDC84, 0)]),
                               startCenter: spot, startRadius: 0, endCenter: spot, endRadius: 440, options: [])

    // Robot and shock marks at 78 %, so the raised arms stay inside the frame.
    context.saveGState()
    context.translateBy(x: 512, y: 440)
    context.scaleBy(x: 0.78, y: 0.78)
    context.translateBy(x: -512, y: -440)

    // "Shock" marks beside the head.
    context.setStrokeColor(color(0xFFD54F))
    for side: CGFloat in [-1, 1] {
        for (offset, length) in [(CGFloat(0), CGFloat(56)), (46, 40), (-46, 40)] {
            let base = CGPoint(x: 512 + side * 318, y: 812 + offset)
            capsule(context, from: base, to: CGPoint(x: base.x + side * length, y: base.y + offset * 0.35), width: 18)
        }
    }

    // Robot, in Android green with a gentle top light.
    let green = gradient([color(0x5BEA9C), color(0x3DDC84), color(0x2AB86C)])
    func fillGreen(_ path: CGPath, top: CGFloat, bottom: CGFloat) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(green, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
    context.setStrokeColor(color(0x3DDC84))
    for (from, to) in Robot.antennas { capsule(context, from: from, to: to, width: 30) }
    for (from, to) in Robot.arms { capsule(context, from: from, to: to, width: 104) }
    fillGreen(Robot.head, top: 770, bottom: 520)
    fillGreen(Robot.body, top: 500, bottom: 40)

    // Face: huge eyes, raised brows, an "O" mouth.
    let dark = color(0x0B1B2B)
    for x: CGFloat in [420, 604] {
        context.setFillColor(color(0xFFFFFF))
        context.fillEllipse(in: CGRect(x: x - 56, y: 598, width: 112, height: 120))
        context.setFillColor(dark)
        context.fillEllipse(in: CGRect(x: x - 22, y: 650, width: 44, height: 48))   // pupils look up
        context.setFillColor(color(0xFFFFFF))
        context.fillEllipse(in: CGRect(x: x - 4, y: 682, width: 14, height: 14))    // catchlight
    }
    context.setStrokeColor(dark)
    for x: CGFloat in [420, 604] {
        context.setLineWidth(16)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: x, y: 672), radius: 68, startAngle: .pi * 0.33, endAngle: .pi * 0.67, clockwise: false)
        context.strokePath()
    }
    context.setFillColor(dark)
    context.fillEllipse(in: CGRect(x: 512 - 34, y: 530, width: 68, height: 56))
    context.restoreGState()

    // Glass: light sheen on the upper half and a thin rim.
    context.drawLinearGradient(gradient([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)]),
                               start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.midY), options: [])
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.2))
    context.setLineWidth(3)
    context.strokePath()

    return png(context)
}

// MARK: - Menu bar icon

/// Robot head with antennas and eye holes, black on clear: macOS tints template images.
func drawMenuBarIcon(scale: Int) -> Data {
    let points: CGFloat = 18
    let pixels = Int(points) * scale
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Fit the head (x 262…762, y 520…860) into the square.
    let unit = CGFloat(pixels) / 600
    context.scaleBy(x: unit, y: unit)
    context.translateBy(x: -212, y: -380)
    context.setFillColor(color(0x000000))
    context.setStrokeColor(color(0x000000))
    context.addPath(Robot.head)
    context.fillPath()
    for (from, to) in Robot.antennas { capsule(context, from: from, to: to, width: 40) }
    context.setBlendMode(.clear)
    for x: CGFloat in [420, 604] { context.fillEllipse(in: CGRect(x: x - 44, y: 610, width: 88, height: 92)) }
    return png(context)
}

func png(_ context: CGContext) -> Data {
    NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

// MARK: - Output

func write(_ data: Data, _ folder: String, _ file: String) throws {
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try data.write(to: URL(filePath: folder).appending(path: file))
}

let appIcon = assets + "/AppIcon.appiconset"
let sizes: [(name: String, points: Int, scale: Int)] = [
    ("16", 16, 1), ("16@2x", 16, 2), ("32", 32, 1), ("32@2x", 32, 2), ("128", 128, 1),
    ("128@2x", 128, 2), ("256", 256, 1), ("256@2x", 256, 2), ("512", 512, 1), ("512@2x", 512, 2),
]
var entries: [String] = []
for entry in sizes {
    let file = "icon_\(entry.name).png"
    try write(drawAppIcon(size: entry.points * entry.scale), appIcon, file)
    entries.append("""
        { "filename": "\(file)", "idiom": "mac", "scale": "\(entry.scale)x", "size": "\(entry.points)x\(entry.points)" }
    """)
}
try ("{\n  \"images\": [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\": { \"author\": \"xcode\", \"version\": 1 }\n}\n")
    .write(toFile: appIcon + "/Contents.json", atomically: true, encoding: .utf8)

let menuBar = assets + "/MenuBarIcon.imageset"
try write(drawMenuBarIcon(scale: 1), menuBar, "menubar.png")
try write(drawMenuBarIcon(scale: 2), menuBar, "menubar@2x.png")
try """
{
  "images": [
    { "filename": "menubar.png", "idiom": "universal", "scale": "1x" },
    { "filename": "menubar@2x.png", "idiom": "universal", "scale": "2x" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": { "template-rendering-intent": "template" }
}
""".write(toFile: menuBar + "/Contents.json", atomically: true, encoding: .utf8)
print("Wrote app icon (\(sizes.count) sizes) and menu bar icon to \(assets)")
