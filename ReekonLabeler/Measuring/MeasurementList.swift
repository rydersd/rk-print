/// The measurements read from the tape this session (S19), newest first. The tool sends a measurement again on
/// every sync, so a repeat of one already listed is dropped.
nonisolated struct MeasurementList: Sendable {
    private(set) var entries: [T1Measurement] = []

    /// Adds a measurement at the top; false when it was already listed.
    @discardableResult
    mutating func add(_ measurement: T1Measurement) -> Bool {
        guard !entries.contains(where: { $0.id == measurement.id }) else { return false }
        entries.insert(measurement, at: 0)
        return true
    }

    mutating func removeAll() { entries.removeAll() }
}
