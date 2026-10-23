import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares a picked photo for the label (S7): upright, at most 1024 px on its longer side, greyscale, PNG.
nonisolated enum PictureImport {
    /// Reads any image format ImageIO knows (HEIC, JPEG, PNG…) without decoding it at full size.
    static func picture(fromImageData data: Data) -> PictureContent? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: PictureContent.maximumPixelSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return picture(from: image)
    }

    /// Flattens `image` onto white (transparency prints as paper) in greyscale, shrinking it if needed.
    static func picture(from image: CGImage) -> PictureContent? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Double(PictureContent.maximumPixelSide) / Double(longest))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let grey = context.makeImage(), let png = pngData(grey) else { return nil }
        return PictureContent(pngData: png, pixelWidth: width, pixelHeight: height)
    }

    /// A greyscale label image as a colour PNG on `stock`: white becomes the stock colour, black stays black.
    static func thumbnailPNG(_ image: CGImage, stock: LabelStock) -> Data? {
        guard stock != .white else { return pngData(image) }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(red: stock.rgb.red, green: stock.rgb.green, blue: stock.rgb.blue, alpha: 1)
        context.fill(rect)
        context.setBlendMode(.multiply)
        context.draw(image, in: rect)
        return context.makeImage().flatMap(pngData)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
