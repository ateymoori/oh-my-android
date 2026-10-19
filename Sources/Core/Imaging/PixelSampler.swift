import CoreGraphics
import Foundation
import ImageIO

/// Reads pixel colors from a screenshot. Decodes once into RGBA8 so sampling is a lookup.
/// ImageIO and Core Graphics only, so it is safe off the main thread.
struct PixelSampler: Sendable {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(png: Data) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        // The context draws into the buffer, so the pointer must stay valid while it does.
        let drawn = buffer.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(
                data: pixels.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        bytes = buffer
    }

    /// Color at a pixel, or nil outside the image.
    func color(at point: CGPoint) -> PixelColor? {
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        // Core Graphics stores premultiplied alpha; report the pixel's own color, as design tools do.
        let alpha = Int(bytes[offset + 3])
        guard alpha > 0 else { return PixelColor(red: 0, green: 0, blue: 0) }
        func channel(_ value: UInt8) -> UInt8 { UInt8(min(255, (Int(value) * 255 + alpha / 2) / alpha)) }
        return PixelColor(red: channel(bytes[offset]), green: channel(bytes[offset + 1]), blue: channel(bytes[offset + 2]))
    }
}

struct PixelColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}
