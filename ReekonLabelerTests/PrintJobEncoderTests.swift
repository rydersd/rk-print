import CoreGraphics
import Testing
@testable import Labeler

struct PrintJobEncoderTests {
    /// Header 2 holds the data length in 16 bits; a job past that would be read short by the printer, so
    /// it is refused instead of sent. A 200 mm custom label of dithered photo gets there.
    @Test func refusesJobTooLongForHeader() {
        var bitmap = Bitmap(width: 384, height: 1584)
        for i in bitmap.dots.indices where (i + i / 384) % 3 == 0 { bitmap.dots[i] = 1 } // adjacent rows differ
        #expect(throws: PrinterError.jobTooLarge) { try PrintJobEncoder.encode(bitmap) }
    }

    @Test func matchesSDKFormat() throws {
        var bitmap = Bitmap(width: 384, height: 2)
        for x in 0..<8 { bitmap[x, 1] = true }
        let job = try PrintJobEncoder.encode(bitmap)

        #expect(job.header1 == [0x3a, 0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0a])
        #expect(job.header2 == [0x3a, 0x30, 0x07, 0x00, 0x10, 0x00, 0x00, 0x05])
        #expect(job.data == [
            0x3c, 0x01, 0x00, 0x30, 0x00,       // white row
            0x3c, 0x01, 0x00, 0x00, 0x2f, 0xff, // dots 0–7 black, 47 white bytes on the right
            0x3c, 0x05, 0x00, 0x30, 0x00,       // the 5 added white rows, merged
        ])
    }

    @Test func rotatedLabelIsHeadWide() throws {
        var doc = LabelDocument(size: .large, orientation: .rotated)
        doc.elements = [.text("PANTRY", originMM: CGPoint(x: 0, y: 1), widthMM: 78, pointSize: 60)]
        let bitmap = PrintJobEncoder.headBitmap(for: doc)
        #expect(bitmap.width == 384)
        #expect(bitmap.height == 624)

        let job = try PrintJobEncoder.encode(bitmap)
        #expect(job.header2[2] == 0x75 && job.header2[3] == 0x02) // 629 rows = 624 + 5

        // Walk every row run: each must fit the 48-byte head and the runs must add up to 629 rows.
        var i = 0, rows = 0
        while i < job.data.count {
            #expect(job.data[i] == 0x3c)
            let count = Int(job.data[i + 1]) | Int(job.data[i + 2]) << 8
            let left = Int(job.data[i + 3]), right = Int(job.data[i + 4])
            #expect(left + right <= 48)
            rows += count
            i += 5 + 48 - left - right
        }
        #expect(i == job.data.count)
        #expect(rows == 629)
    }

    @Test func narrowBitmapPadsRightInset() throws {
        var bitmap = Bitmap(width: 320, height: 1)
        bitmap[0, 0] = true
        let job = try PrintJobEncoder.encode(bitmap)
        // 40 bytes wide: 39 white bytes on the right of this row, plus 8 the narrow image never covers.
        #expect(Array(job.data.prefix(6)) == [0x3c, 0x01, 0x00, 0x00, 47, 0x80])
    }
}
