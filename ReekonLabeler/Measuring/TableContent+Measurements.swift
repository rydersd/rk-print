import Foundation

extension TableContent {
    /// A table of picked measurements in the order picked (S21): three read as L, W, D and two as L, W; any
    /// other count gets blank labels. Fewer than two still gives two rows, like a new table.
    nonisolated static func fromMeasurements(_ measurements: [T1Measurement], unit: MeasurementUnit) -> TableContent {
        let labels = switch measurements.count {
        case 2: ["L", "W"]
        case 3: ["L", "W", "D"]
        default: [String](repeating: "", count: measurements.count)
        }
        var rows = zip(labels, measurements).map { label, measurement in
            TableRow(label: label, value: MeasurementFormat.format(positionUM: measurement.positionUM, unit: unit))
        }
        while rows.count < 2 { rows.append(TableRow()) }
        return TableContent(rows: rows)
    }
}
