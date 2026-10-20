import SwiftUI

/// Colour tokens. Label stock is always white because it previews paper, in light and dark mode alike.
enum Theme {
    static let canvasBackground = Color(.secondarySystemBackground)
    static let labelStock = Color.white
    static let labelEdge = Color(.separator)
    static let unprintableHatch = Color(.systemGray3)
    static let gridDot = Color(.systemGray2)
    static let selection = Color.accentColor
    static let handle = Color.accentColor
}
