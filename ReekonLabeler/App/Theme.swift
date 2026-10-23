import SwiftUI

/// Colour tokens. Label stock previews the loaded roll, so it is the same in light and dark mode.
enum Theme {
    static let canvasBackground = Color(.secondarySystemBackground)
    static func labelStock(_ stock: LabelStock) -> Color {
        Color(.sRGB, red: stock.rgb.red, green: stock.rgb.green, blue: stock.rgb.blue)
    }
    static let labelEdge = Color(.separator)
    static let unprintableHatch = Color(.systemGray3)
    static let gridDot = Color(.systemGray2)
    /// A stroke being drawn, before the bitmap shows it (S14): what the printer prints.
    static let ink = Color.black
    static let selection = Color.accentColor
    static let handle = Color.accentColor
    /// Covers the part of a picture the crop will cut away.
    static let cropDim = Color.black.opacity(0.5)
}
