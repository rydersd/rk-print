import CoreGraphics
import CoreText
import Foundation

/// Draws a label into the 1-bit bitmap that both the canvas and the printer use.
/// The bitmap covers the printable area only, at 8 dots per mm, in label-space orientation.
enum LabelRenderer {
    static func render(_ document: LabelDocument, layouts: [UUID: BlockLayout]? = nil) -> Bitmap {
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

        for block in document.blocks where !block.text.isEmpty {
            let layout = layouts?[block.id] ?? LayoutEngine.layout(block, in: geometry)
            let frame = geometry.dotRect(forMM: layout.frameMM)
            let font = FontCatalog.ctFont(block.font, pointSize: layout.effectivePointSize * LayoutEngine.dotsPerPoint)
            let framesetter = CTFramesetterCreateWithAttributedString(LayoutEngine.attributedText(block, font: font))
            // Core Graphics counts y from the bottom; lines are set from the top of the path.
            let path = CGPath(rect: CGRect(x: frame.minX, y: 0, width: frame.width, height: CGFloat(height) - frame.minY),
                              transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
        }

        guard let data = context.data else { return Bitmap(width: width, height: height) }
        let gray = data.bindMemory(to: UInt8.self, capacity: width * height)
        var bitmap = Bitmap(width: width, height: height)
        for i in 0..<(width * height) where gray[i] < 128 { bitmap.dots[i] = 1 }
        return bitmap
    }
}
