import AppKit
import CoreGraphics

/// Reads pixel colors from a screenshot. Decodes once into RGBA8 so sampling is a lookup.
final class PixelSampler: @unchecked Sendable {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(png: Data) {
        guard let image = NSImage(data: png), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        width = cgImage.width
        height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// Color at a pixel, or nil outside the image.
    func color(at point: CGPoint) -> PixelColor? {
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        return PixelColor(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
    }
}

struct PixelColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}
