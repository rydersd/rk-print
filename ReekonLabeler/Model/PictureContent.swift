import CoreGraphics
import Foundation

/// A picture on the label (S7). The stored image is greyscale, at most 1024 px on its longer side, and is
/// kept whole so a later crop can widen again (S8). How it becomes dots is decided at render time.
nonisolated struct PictureContent: Codable, Hashable, Sendable {
    /// Identifies `pngData` for the decoded-pixel cache; a new image gets a new ID.
    var imageID = UUID()
    var pngData: Data
    var pixelWidth: Int
    var pixelHeight: Int
    /// The part of the image shown, in unit coordinates of the whole image (top-left origin).
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Hard black/white cut instead of dithering, for logos and line art.
    var lineArt = false
    /// −1 (darker) … +1 (lighter), applied before dithering or the cut.
    var brightness = 0.0

    static let maximumPixelSide = 1024
    /// Smallest crop side, as a fraction of the image, so a crop can't collapse to nothing.
    static let minimumCropFraction = 0.02

    /// Height ÷ width of the cropped picture.
    var aspect: Double {
        let w = crop.width * Double(pixelWidth), h = crop.height * Double(pixelHeight)
        return w > 0 ? h / w : 1
    }
}
