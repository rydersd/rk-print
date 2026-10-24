import CoreGraphics
import CoreText
import Foundation

/// Where a table's lines and cells go (S20), in whole dots so the canvas, the cell fields and the print agree.
/// Positions are mm from the table's top-left, before rotation.
nonisolated enum TableLayout {
    static let titleFont = FontSpec(family: FontCatalog.systemFamily, face: "Bold")
    static let bodyFont = FontSpec(family: FontCatalog.systemFamily, face: "Regular")
    /// Space between a cell's text and its lines.
    static let paddingDots = 4.0
    static let lineDots = 1.0
    /// The label column's share of the width; values take the rest.
    static let labelColumnFraction = 0.4
    private static let fitStep = 0.5

    /// One row's height: a line of text plus padding above and below.
    static func rowHeightMM(pointSize: Double) -> Double {
        let font = FontCatalog.ctFont(titleFont, pointSize: pointSize * LayoutEngine.dotsPerPoint)
        let line = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
        return (line + 2 * paddingDots) / LabelGeometry.dotsPerMM
    }

    /// The title row plus one row per measurement.
    static func heightMM(_ table: TableContent, pointSize: Double) -> Double {
        rowHeightMM(pointSize: pointSize) * Double(table.rows.count + 1)
    }

    /// The largest size ≤ the requested size, in 0.5 pt steps, at which the table fits `availableMM`.
    static func fittedPointSize(_ table: TableContent, availableMM: Double) -> Double {
        let requested = LayoutEngine.clamp(table.pointSize, TextContent.minimumPointSize, TextContent.maximumPointSize)
        var size = requested
        while size > TextContent.minimumPointSize, heightMM(table, pointSize: size) > availableMM { size -= fitStep }
        return max(size, TextContent.minimumPointSize)
    }

    /// Whether one more row still fits `availableMM` at the smallest text size, so a table never outgrows the label.
    static func canAddRow(_ table: TableContent, availableMM: Double) -> Bool {
        var grown = table
        grown.rows.append(TableRow())
        return heightMM(grown, pointSize: TextContent.minimumPointSize) <= availableMM
    }

    /// The x of the line between labels and values, in mm.
    static func dividerMM(widthMM: Double) -> Double {
        (widthMM * LabelGeometry.dotsPerMM * labelColumnFraction).rounded() / LabelGeometry.dotsPerMM
    }

    /// Every cell and its box, title first, then each row's label and value.
    static func cells(_ table: TableContent, sizeMM: CGSize) -> [(cell: TableCell, frameMM: CGRect)] {
        let rowHeight = sizeMM.height / Double(table.rows.count + 1)
        let divider = dividerMM(widthMM: sizeMM.width)
        var cells: [(TableCell, CGRect)] = [(.title, CGRect(x: 0, y: 0, width: sizeMM.width, height: rowHeight))]
        for row in table.rows.indices {
            let y = rowHeight * Double(row + 1)
            cells.append((.label(row), CGRect(x: 0, y: y, width: divider, height: rowHeight)))
            cells.append((.value(row), CGRect(x: divider, y: y, width: sizeMM.width - divider, height: rowHeight)))
        }
        return cells
    }

    static func font(for cell: TableCell) -> FontSpec { cell == .title ? titleFont : bodyFont }

    static func alignment(for cell: TableCell) -> TextAlignmentOption {
        switch cell {
        case .title: .center
        case .label: .left
        case .value: .right
        }
    }
}
