#!/usr/bin/env swift
// Draws the Oyama app icon with Core Graphics and writes every size the asset catalog needs.
// Usage: Scripts/make-icon.swift [output-folder]   (default: Sources/App/Assets.xcassets/AppIcon.appiconset)
//
// Motif: Mt. Ōyama at dawn. A sharp snow-capped peak against a sunrise sky, green foothills in front
// (a nod to Android). Layout follows the macOS icon grid: 824 pt body inside a 1024 pt canvas.
import AppKit
import CoreGraphics

let output = CommandLine.arguments.dropFirst().first ?? "Sources/App/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func linearGradient(_ context: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Closed polygon through the points, filled with a vertical gradient (top color first).
func ridge(_ context: CGContext, _ points: [CGPoint], top: CGColor, bottom: CGColor, body: CGRect) {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    context.saveGState()
    context.addPath(path)
    context.clip()
    let maxY = points.map(\.y).max()!
    linearGradient(context, [top, bottom], from: CGPoint(x: 0, y: maxY), to: CGPoint(x: 0, y: body.minY))
    context.restoreGState()
}

func drawIcon(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow, as on system icons.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x1B2350))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // Dawn sky: deep indigo at the top, warm peach at the horizon.
    linearGradient(context, [color(0x141B4D), color(0x4A3F8F), color(0xE9866A), color(0xFFC98B)],
                   from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY + 250))

    // Rising sun beside the summit.
    let sun = CGPoint(x: 700, y: 650)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xFFE3A3, 0.9), color(0xFFB36B, 0.0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 260, options: [])
    context.setFillColor(color(0xFFF1CF))
    context.fillEllipse(in: CGRect(x: sun.x - 78, y: sun.y - 78, width: 156, height: 156))

    // Distant range.
    ridge(context, [CGPoint(x: 60, y: 430), CGPoint(x: 250, y: 560), CGPoint(x: 360, y: 500), CGPoint(x: 700, y: 600),
                    CGPoint(x: 980, y: 440), CGPoint(x: 980, y: 60), CGPoint(x: 60, y: 60)],
          top: color(0x7C6FB8), bottom: color(0x3E3A7A), body: body)

    // Mt. Ōyama: a steep, symmetric pyramid.
    let summit = CGPoint(x: 512, y: 780)
    let left = CGPoint(x: 150, y: 250), right = CGPoint(x: 874, y: 250)
    ridge(context, [left, summit, right, CGPoint(x: 874, y: 60), CGPoint(x: 150, y: 60)],
          top: color(0x2B3A78), bottom: color(0x151C45), body: body)
    // Sunlit left face.
    ridge(context, [left, summit, CGPoint(x: 470, y: 250)],
          top: color(0x4B5CA8), bottom: color(0x27336D), body: body)

    // Snow cap with a jagged lower edge.
    let snow = CGMutablePath()
    snow.addLines(between: [
        summit, CGPoint(x: 598, y: 655), CGPoint(x: 566, y: 672), CGPoint(x: 540, y: 640),
        CGPoint(x: 505, y: 668), CGPoint(x: 472, y: 638), CGPoint(x: 448, y: 660), CGPoint(x: 426, y: 655),
    ])
    snow.closeSubpath()
    context.addPath(snow)
    context.setFillColor(color(0xF7F8FF))
    context.fillPath()
    // Shade on the snow's right half.
    let snowShade = CGMutablePath()
    snowShade.addLines(between: [summit, CGPoint(x: 598, y: 655), CGPoint(x: 566, y: 672), CGPoint(x: 540, y: 640), CGPoint(x: 512, y: 662)])
    snowShade.closeSubpath()
    context.addPath(snowShade)
    context.setFillColor(color(0xC9CFF0))
    context.fillPath()

    // Green foothills in front.
    ridge(context, [CGPoint(x: 60, y: 330), CGPoint(x: 260, y: 400), CGPoint(x: 470, y: 300), CGPoint(x: 700, y: 380),
                    CGPoint(x: 980, y: 290), CGPoint(x: 980, y: 60), CGPoint(x: 60, y: 60)],
          top: color(0x3DDC84), bottom: color(0x0F7A4A), body: body)
    ridge(context, [CGPoint(x: 60, y: 230), CGPoint(x: 330, y: 300), CGPoint(x: 620, y: 215), CGPoint(x: 980, y: 260),
                    CGPoint(x: 980, y: 60), CGPoint(x: 60, y: 60)],
          top: color(0x1FAF68), bottom: color(0x0A5234), body: body)

    // Glass: a light sheen on the upper half and a thin rim.
    linearGradient(context, [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)],
                   from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.midY))
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.22))
    context.setLineWidth(3)
    context.strokePath()

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("16", 16, 1), ("16@2x", 16, 2), ("32", 32, 1), ("32@2x", 32, 2), ("128", 128, 1),
    ("128@2x", 128, 2), ("256", 256, 1), ("256@2x", 256, 2), ("512", 512, 1), ("512@2x", 512, 2),
]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
var images: [String] = []
for entry in sizes {
    let file = "icon_\(entry.name).png"
    try drawIcon(size: entry.points * entry.scale).write(to: URL(filePath: output).appending(path: file))
    images.append("""
        { "filename": "\(file)", "idiom": "mac", "scale": "\(entry.scale)x", "size": "\(entry.points)x\(entry.points)" }
    """)
}
let contents = "{\n  \"images\": [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\": { \"author\": \"xcode\", \"version\": 1 }\n}\n"
try contents.write(toFile: output + "/Contents.json", atomically: true, encoding: .utf8)
print("Wrote \(sizes.count) icons to \(output)")
