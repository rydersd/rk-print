import Foundation

/// The three writes of one P1L label (SDK Figure 22).
struct PrintJob: Equatable, Sendable {
    var header1: [UInt8]
    var header2: [UInt8]
    var data: [UInt8]
}

/// Turns a bitmap into a P1L print job. Port of SDK Example 7.
enum PrintJobEncoder {
    static let header1: [UInt8] = [0x3a, 0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0a]
    static let headBytes = LabelSize.headMaxDots / 8
    /// White rows added below the image; the printer can drop shapes that end near the bottom.
    static let trailingWhiteRows = 5
    private static let rowRunMarker: UInt8 = 0x3c

    /// The label rendered and turned so its rows run across the head.
    static func headBitmap(for document: LabelDocument) -> Bitmap {
        let bitmap = LabelRenderer.render(document)
        return document.orientation == .rotated ? bitmap.rotatedClockwise() : bitmap
    }

    /// Throws `PrinterError.jobTooLarge` rather than send a job whose length Header 2 cannot hold.
    static func encode(_ bitmap: Bitmap) throws -> PrintJob {
        let rowBytes = min(headBytes, (bitmap.width + 7) / 8)
        var rows = (0..<bitmap.height).map { packedRow(bitmap, y: $0, bytes: rowBytes) }
        rows += Array(repeating: [UInt8](repeating: 0, count: rowBytes), count: trailingWhiteRows)

        var data: [UInt8] = []
        var y = 0
        while y < rows.count {
            var count = 1
            while y + count < rows.count, count < Int(UInt16.max), rows[y + count] == rows[y] { count += 1 }
            data += rowRun(rows[y], count: count)
            y += count
        }

        guard let length = UInt16(exactly: data.count) else { throw PrinterError.jobTooLarge }
        let height = UInt16(clamping: rows.count)
        let header2: [UInt8] = [0x3a, UInt8(headBytes), UInt8(height & 0xff), UInt8(height >> 8),
                                UInt8(length & 0xff), UInt8(length >> 8), 0x00, 0x05]
        return PrintJob(header1: header1, header2: header2, data: data)
    }

    /// One row as bytes, 8 dots per byte, leftmost dot in bit 7, clipped to the head.
    private static func packedRow(_ bitmap: Bitmap, y: Int, bytes: Int) -> [UInt8] {
        var row = [UInt8](repeating: 0, count: bytes)
        let start = y * bitmap.width
        for x in 0..<min(bitmap.width, bytes * 8) where bitmap.dots[start + x] != 0 {
            row[x >> 3] |= 0x80 >> UInt8(x & 7)
        }
        return row
    }

    /// A row run (SDK Figure 23): marker, count, left and right white-byte insets, then the bytes between.
    private static func rowRun(_ row: [UInt8], count: Int) -> [UInt8] {
        let header: [UInt8] = [rowRunMarker, UInt8(count & 0xff), UInt8(count >> 8)]
        guard let first = row.firstIndex(where: { $0 != 0 }), let last = row.lastIndex(where: { $0 != 0 }) else {
            return header + [UInt8(headBytes), 0x00]
        }
        // A row narrower than the head prints from the left; the missing bytes count as right inset.
        let narrow = headBytes - row.count
        return header + [UInt8(first), UInt8(row.count - 1 - last + narrow)] + row[first...last]
    }
}
