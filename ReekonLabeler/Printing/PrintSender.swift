import Foundation

/// Where print bytes go. The real one is the P1L's Print characteristic (0xAE01); tests use a fake.
protocol PrintTransport: AnyObject {
    /// Largest single write without response, in bytes.
    var maximumWriteLength: Int { get }
    func writeWithoutResponse(_ bytes: [UInt8]) async throws
}

/// Sends print jobs at the pace the P1L needs (SDK Usage Sequence steps 5–6): headers, then the image in
/// chunks 12 ms apart, then a pause before the next label because the printer drops headers while printing.
final class PrintSender {
    static let fallbackWriteLength = 180

    private let transport: any PrintTransport
    private let chunkInterval: Duration
    private(set) var readyAt: ContinuousClock.Instant?

    init(transport: any PrintTransport, chunkInterval: Duration = .milliseconds(12)) {
        self.transport = transport
        self.chunkInterval = chunkInterval
    }

    static func cooldown(feedMM: Double) -> Duration {
        feedMM <= 30 ? .milliseconds(1500) : .milliseconds(2500)
    }

    func send(_ job: PrintJob, feedMM: Double) async throws {
        if let readyAt { try await Task.sleep(until: readyAt, clock: .continuous) }
        let chunkSize = transport.maximumWriteLength > 0 ? transport.maximumWriteLength : Self.fallbackWriteLength

        try await transport.writeWithoutResponse(job.header1)
        try await Task.sleep(for: chunkInterval)
        try await transport.writeWithoutResponse(job.header2)
        var offset = 0
        while offset < job.data.count {
            try await Task.sleep(for: chunkInterval)
            let end = min(offset + chunkSize, job.data.count)
            try await transport.writeWithoutResponse(Array(job.data[offset..<end]))
            offset = end
        }
        readyAt = .now + Self.cooldown(feedMM: feedMM)
    }
}
