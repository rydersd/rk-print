import CoreGraphics
import Testing
@testable import Labeler

struct TableLayoutTests {
    /// S26: a long value shrinks until it fits its cell; the title and the other cells keep the table's size.
    @Test func longCellShrinksAlone() throws {
        let table = TableContent(title: "BOLTS", rows: [TableRow(label: "Length", value: "1234.5 mm × 6789.0 mm"),
                                                       TableRow(label: "Width", value: "12 mm")], pointSize: 12)
        let size = CGSize(width: 46, height: TableLayout.heightMM(table, pointSize: 12))
        let cells = TableLayout.cells(table, sizeMM: size)
        func pointSize(_ cell: TableCell) throws -> Double {
            let frame = try #require(cells.first { $0.cell == cell }).frameMM
            return TableLayout.cellPointSize(table, cell: cell, tablePointSize: 12, cellWidthMM: frame.width)
        }

        let long = try pointSize(.value(0))
        #expect(long < 12 && long >= TextContent.minimumPointSize)
        let frame = try #require(cells.first { $0.cell == .value(0) }).frameMM
        #expect(TableLayout.textWidthDots(table[.value(0)], cell: .value(0), pointSize: long)
                <= frame.width * LabelGeometry.dotsPerMM - 2 * TableLayout.paddingDots)
        for cell in [TableCell.title, .label(0), .label(1), .value(1)] { #expect(try pointSize(cell) == 12) }
    }
}
