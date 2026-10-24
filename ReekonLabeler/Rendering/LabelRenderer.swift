import CoreGraphics
import CoreText
import Foundation

/// Draws a label into the 1-bit bitmap that both the canvas and the printer use.
/// The bitmap covers the printable area only, at 8 dots per mm, in label-space orientation.
nonisolated enum LabelRenderer {
    static func render(_ document: LabelDocument, layouts: [UUID: ElementLayout]? = nil) -> Bitmap {
        let geometry = document.geometry
        let width = geometry.bitmapWidth, height = geometry.bitmapHeight
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return Bitmap(width: max(width, 0), height: max(height, 0)) }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The printer has no gray: draw hard edges so the threshold below matches what was drawn.
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
        context.setShouldSmoothFonts(false)
        context.interpolationQuality = .none

        for element in document.elements {
            let layout = layouts?[element.id] ?? LayoutEngine.layout(element, in: geometry)
            draw(element, layout: layout, geometry: geometry, bitmapHeight: height, in: context)
        }

        guard let data = context.data else { return Bitmap(width: width, height: height) }
        let gray = data.bindMemory(to: UInt8.self, capacity: width * height)
        var bitmap = Bitmap(width: width, height: height)
        for i in 0..<(width * height) where gray[i] < 128 { bitmap.dots[i] = 1 }
        return bitmap
    }

    /// Draws one element's content centred in its footprint, turned clockwise by its rotation.
    private static func draw(_ element: LabelElement, layout: ElementLayout, geometry: LabelGeometry,
                             bitmapHeight: Int, in context: CGContext) {
        let footprint = geometry.dotRect(forMM: layout.frameMM)
        let contentWidth = (layout.contentSizeMM.width * LabelGeometry.dotsPerMM).rounded()
        let contentHeight = (layout.contentSizeMM.height * LabelGeometry.dotsPerMM).rounded()
        guard contentWidth >= 1, contentHeight >= 1 else { return }
        // Whole-dot footprint so a quarter turn lands the content's corners on whole dots.
        let sideways = element.rotation.isSideways
        let originX = footprint.minX.rounded(), originY = footprint.minY.rounded()
        let footprintWidth = sideways ? contentHeight : contentWidth
        let footprintHeight = sideways ? contentWidth : contentHeight
        let content = CGRect(x: -contentWidth / 2, y: -contentHeight / 2, width: contentWidth, height: contentHeight)

        context.saveGState()
        defer { context.restoreGState() }
        // Core Graphics counts y from the bottom; a negative angle there is clockwise on the label.
        context.translateBy(x: originX + footprintWidth / 2, y: CGFloat(bitmapHeight) - originY - footprintHeight / 2)
        context.rotate(by: -CGFloat(element.rotation.rawValue) * .pi / 180)
        context.clip(to: content)

        switch element.content {
        case .text(let text):
            guard !text.text.isEmpty else { return }
            let font = FontCatalog.ctFont(text.font, pointSize: layout.effectivePointSize * LayoutEngine.dotsPerPoint)
            let framesetter = CTFramesetterCreateWithAttributedString(LayoutEngine.attributedText(text, font: font))
            // Lines are set from the top of the path; extend it downward so rounding never drops a last line.
            let path = CGPath(rect: CGRect(x: content.minX, y: content.minY - contentHeight,
                                           width: contentWidth, height: contentHeight * 2), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
        case .picture(let picture):
            guard let dots = PictureRasterizer.dots(for: picture, width: Int(contentWidth), height: Int(contentHeight))
            else { return }
            context.draw(dots, in: content)
        case .scribble(let scribble):
            // Points are mm down from the top-left; Core Graphics y runs up from the bottom.
            let dotsPerUnit = contentWidth / scribble.sizeMM.width
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: content.minX + p.x * dotsPerUnit, y: content.maxY - p.y * dotsPerUnit)
            }
            let path = CGMutablePath()
            for stroke in scribble.strokes {
                guard let first = stroke.first else { continue }
                path.move(to: point(first))
                // A tap is a one-point stroke; a zero-length line with round caps prints it as a dot.
                for p in stroke.count > 1 ? Array(stroke.dropFirst()) : [first] { path.addLine(to: point(p)) }
            }
            context.setStrokeColor(gray: 0, alpha: 1)
            context.setLineWidth(scribble.penWidthMM * dotsPerUnit)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path)
            context.strokePath()
        case .table(let table):
            drawTable(table, pointSize: layout.effectivePointSize, sizeMM: layout.contentSizeMM, in: content,
                      context: context)
        }
    }

    /// A box with a line under the title and between rows, a line between labels and values, and each cell's
    /// text on one line, clipped to its cell (S20).
    private static func drawTable(_ table: TableContent, pointSize: Double, sizeMM: CGSize, in content: CGRect,
                                  context: CGContext) {
        let dots = LabelGeometry.dotsPerMM, line = TableLayout.lineDots
        // Table mm count down from the top-left; Core Graphics y runs up from the bottom.
        func rect(_ mm: CGRect) -> CGRect {
            CGRect(x: content.minX + (mm.minX * dots).rounded(), y: content.maxY - (mm.maxY * dots).rounded(),
                   width: (mm.width * dots).rounded(), height: (mm.height * dots).rounded())
        }
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.stroke(content.insetBy(dx: line / 2, dy: line / 2), width: line)
        let cells = TableLayout.cells(table, sizeMM: sizeMM)
        for (cell, frameMM) in cells {
            let box = rect(frameMM)
            // The line under each row but the last, which the box already draws.
            if box.minY > content.minY + line / 2 {
                context.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: line))
            }
            if case .value = cell { context.fill(CGRect(x: box.minX, y: box.minY, width: line, height: box.height)) }

            let text = table[cell]
            guard !text.isEmpty else { continue }
            // A long entry shrinks to fit its cell (S26), on the same baseline as full-size text in the row.
            let rowFont = FontCatalog.ctFont(TableLayout.font(for: cell),
                                             pointSize: pointSize * LayoutEngine.dotsPerPoint)
            let cellSize = TableLayout.cellPointSize(table, cell: cell, tablePointSize: pointSize,
                                                     cellWidthMM: frameMM.width)
            let font = FontCatalog.ctFont(TableLayout.font(for: cell), pointSize: cellSize * LayoutEngine.dotsPerPoint)
            let ctLine = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, [
                kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
            ] as CFDictionary))
            let inner = box.insetBy(dx: TableLayout.paddingDots, dy: TableLayout.paddingDots)
            let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            let x: CGFloat = switch TableLayout.alignment(for: cell) {
            case .left: inner.minX
            case .center: inner.midX - width / 2
            case .right: inner.maxX - width
            }
            context.saveGState()
            context.clip(to: inner)
            context.textPosition = CGPoint(x: x.rounded(), y: (inner.maxY - CTFontGetAscent(rowFont)).rounded())
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
    }
}
