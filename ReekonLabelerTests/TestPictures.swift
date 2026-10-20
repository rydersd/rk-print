import CoreGraphics
import Foundation
@testable import Labeler

/// Builds small greyscale pictures for tests, pixel by pixel.
enum TestPictures {
    /// `grey(x, y)` gives each pixel's level, 0 black … 255 white, with (0, 0) at the top-left.
    static func make(width: Int, height: Int, grey: (Int, Int) -> UInt8) -> PictureContent {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { pixels[y * width + x] = grey(x, y) }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return PictureImport.picture(from: image)!
    }

    static func element(_ picture: PictureContent, x: Double, y: Double, width: Double) -> LabelElement {
        LabelElement(originMM: CGPoint(x: x, y: y), widthMM: width, content: .picture(picture))
    }
}
