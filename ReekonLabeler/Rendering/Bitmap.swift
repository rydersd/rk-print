import CoreGraphics
import Foundation

/// A 1-bit image, one byte per dot (1 = black), rows top to bottom. This is what the P1L prints.
nonisolated struct Bitmap: Equatable, Sendable {
    let width: Int
    let height: Int
    var dots: [UInt8]

    init(width: Int, height: Int, dots: [UInt8]? = nil) {
        self.width = width
        self.height = height
        self.dots = dots ?? [UInt8](repeating: 0, count: width * height)
    }

    subscript(x: Int, y: Int) -> Bool {
        get { dots[y * width + x] != 0 }
        set { dots[y * width + x] = newValue ? 1 : 0 }
    }

    /// Number of black dots inside `rect` (in dots, clipped to the bitmap).
    func inkCount(inDots rect: CGRect) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down))), maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down))), maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        var count = 0
        for y in minY..<maxY {
            let row = y * width
            for x in minX..<maxX where dots[row + x] != 0 { count += 1 }
        }
        return count
    }

    /// The bitmap turned 90° clockwise: the left column becomes the top row.
    func rotatedClockwise() -> Bitmap {
        var out = Bitmap(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width where dots[y * width + x] != 0 {
                out.dots[x * out.width + (height - 1 - y)] = 1
            }
        }
        return out
    }

    /// A grayscale image for display: black dots black, the rest white.
    func cgImage() -> CGImage? {
        let pixels = dots.map { $0 != 0 ? UInt8(0) : UInt8(255) }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
