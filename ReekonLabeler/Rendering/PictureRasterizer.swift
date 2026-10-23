import CoreGraphics
import Foundation
import ImageIO
import os

/// Turns a stored picture into black and white dots at the size it prints (S7, S8): crop, scale to the
/// final dot size, shift brightness, then dither (Floyd–Steinberg) or cut at mid-grey for line art.
nonisolated enum PictureRasterizer {
    /// An image of `width` × `height` pixels, each 0 (ink) or 255 (paper).
    static func dots(for picture: PictureContent, width: Int, height: Int) -> CGImage? {
        let key = Key(imageID: picture.imageID, crop: picture.crop, width: width, height: height,
                      lineArt: picture.lineArt, brightness: picture.brightness)
        if let cached = cache.withLock({ $0.dots[key] }) { return cached }
        guard let source = decoded(picture), let grey = scaledGrey(source, crop: picture.crop, width: width,
                                                                  height: height)
        else { return nil }
        let image = makeImage(threshold(grey, width: width, height: height, picture: picture), width: width,
                              height: height)
        if let image {
            // Keep only the latest rendering of each picture: a drag re-renders at one size many times.
            cache.withLock { state in
                state.dots = state.dots.filter { $0.key.imageID != picture.imageID }
                state.dots[key] = image
            }
        }
        return image
    }

    /// Greyscale pixels of the cropped picture scaled to the dot size, white where the picture is clear.
    static func scaledGrey(_ image: CGImage, crop: CGRect, width: Int, height: Int) -> [UInt8]? {
        let pixelCrop = CGRect(x: crop.minX * Double(image.width), y: crop.minY * Double(image.height),
                               width: crop.width * Double(image.width), height: crop.height * Double(image.height))
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard width > 0, height > 0, !pixelCrop.isEmpty, let cropped = image.cropping(to: pixelCrop),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: width * height),
                                         count: width * height))
    }

    /// Brightness shift, then a hard cut (line art) or error diffusion, giving 0 or 255 per pixel.
    static func threshold(_ grey: [UInt8], width: Int, height: Int, picture: PictureContent) -> [UInt8] {
        let shift = Float(picture.brightness) * 128
        var levels = grey.map { min(255, max(0, Float($0) + shift)) }
        var out = [UInt8](repeating: 255, count: levels.count)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let ink = levels[i] < 128
                out[i] = ink ? 0 : 255
                guard !picture.lineArt else { continue }
                let error = levels[i] - (ink ? 0 : 255)
                if x + 1 < width { levels[i + 1] += error * 7 / 16 }
                guard y + 1 < height else { continue }
                if x > 0 { levels[i + width - 1] += error * 3 / 16 }
                levels[i + width] += error * 5 / 16
                if x + 1 < width { levels[i + width + 1] += error * 1 / 16 }
            }
        }
        return out
    }

    // MARK: Decoding and caching

    /// The stored PNG decoded once per image.
    static func decoded(_ picture: PictureContent) -> CGImage? {
        if let cached = cache.withLock({ $0.decoded[picture.imageID] }) { return cached }
        guard let source = CGImageSourceCreateWithData(picture.pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Logger.rendering.error("picture \(picture.imageID, privacy: .public) did not decode")
            return nil
        }
        cache.withLock { $0.decoded[picture.imageID] = image }
        return image
    }

    private static func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private struct Key: Hashable {
        let imageID: UUID
        let crop: CGRect
        let width: Int
        let height: Int
        let lineArt: Bool
        let brightness: Double
    }

    private struct CacheState {
        var decoded: [UUID: CGImage] = [:]
        var dots: [Key: CGImage] = [:]
    }

    private static let cache = OSAllocatedUnfairLock(initialState: CacheState())
}

extension Logger {
    nonisolated static let rendering = Logger(subsystem: "tools.reekon.labeler", category: "rendering")
}
