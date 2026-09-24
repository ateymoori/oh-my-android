import CoreGraphics
import Foundation
import ImageIO

/// Resizes screenshots. A 1080x2400 capture costs a model about 3.5k tokens; at 1 px = 1 dp it costs
/// about a sixth of that, and its coordinates match the UI tree.
enum ImageScaler {
    static func jpeg(fromPNG png: Data, scale: Double, quality: Double = 0.85) throws -> (data: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AppError("The screenshot is not a valid PNG.")
        }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw AppError("Could not resize the screenshot.") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw AppError("Could not resize the screenshot.") }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw AppError("Could not encode the screenshot.")
        }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppError("Could not encode the screenshot.") }
        return (output as Data, width, height)
    }
}
