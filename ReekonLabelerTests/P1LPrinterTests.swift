import Foundation
import Testing
@testable import Labeler

private final class RecordingTransport: PrintTransport {
    let maximumWriteLength = 180
    var writes: [(bytes: [UInt8], at: ContinuousClock.Instant)] = []

    func writeWithoutResponse(_ bytes: [UInt8]) async throws {
        writes.append((bytes, .now))
    }
}

struct P1LPrinterTests {
    @Test func chunksArePacedAndSized() async throws {
        var bitmap = Bitmap(width: 384, height: 240)
        for i in bitmap.dots.indices where (i + i / 384) % 3 == 0 { bitmap.dots[i] = 1 } // diagonal: adjacent rows differ
        let job = try PrintJobEncoder.encode(bitmap)
        #expect(job.data.count > 180 * 3)

        let transport = RecordingTransport()
        let sender = PrintSender(transport: transport)
        try await sender.send(job, feedMM: 30)
        let firstJobWrites = transport.writes.count
        try await sender.send(job, feedMM: 30)

        #expect(transport.writes.allSatisfy { $0.bytes.count <= 180 })
        let first = transport.writes[..<firstJobWrites]
        #expect(first[0].bytes == job.header1)
        #expect(first[1].bytes == job.header2)
        #expect(Array(first.dropFirst(2).flatMap(\.bytes)) == job.data)
        for (a, b) in zip(first, first.dropFirst()) {
            #expect(b.at - a.at >= .milliseconds(12))
        }
        let gap = transport.writes[firstJobWrites].at - transport.writes[firstJobWrites - 1].at
        #expect(gap >= .milliseconds(1500))
    }
}
