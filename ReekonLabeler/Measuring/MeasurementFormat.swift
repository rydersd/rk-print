import Foundation

/// The app-wide unit for tape readings, chosen in the tape sheet (S21).
nonisolated enum MeasurementUnit: String, CaseIterable, Identifiable, Sendable {
    case fractionalInches, feetInches, millimetres, centimetres

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fractionalInches: "Inches"
        case .feetInches: "Feet and inches"
        case .millimetres: "mm"
        case .centimetres: "cm"
        }
    }
}

/// A tape reading as text: inches to the nearest 1/16 (`25 3/8"`), feet and inches (`2' 1 3/8"`), whole mm
/// (`645 mm`) or cm to one decimal (`64.5 cm`). A negative (relative) reading keeps its minus sign.
nonisolated enum MeasurementFormat {
    static let micrometresPerInch = 25_400.0

    static func format(positionUM: Int32, unit: MeasurementUnit) -> String {
        let um = Double(positionUM)
        switch unit {
        case .fractionalInches, .feetInches:
            let sixteenths = Int((abs(um) / micrometresPerInch * 16).rounded())
            guard sixteenths > 0 else { return "0\"" }
            let sign = um < 0 ? "-" : ""
            let feet = unit == .feetInches ? sixteenths / (12 * 16) : 0
            let inches = inchesText(sixteenths - feet * 12 * 16)
            return feet > 0 ? "\(sign)\(feet)' \(inches ?? "0")\"" : "\(sign)\(inches ?? "0")\""
        case .millimetres:
            return "\(signed(um / 1000, digits: 0)) mm"
        case .centimetres:
            return "\(signed(um / 10_000, digits: 1)) cm"
        }
    }

    /// "25 3/8", "25", "3/8", or nil for zero.
    private static func inchesText(_ sixteenths: Int) -> String? {
        let whole = sixteenths / 16
        var numerator = sixteenths % 16, denominator = 16
        while numerator > 0, numerator % 2 == 0 { numerator /= 2; denominator /= 2 }
        switch (whole, numerator) {
        case (0, 0): return nil
        case (_, 0): return "\(whole)"
        case (0, _): return "\(numerator)/\(denominator)"
        default: return "\(whole) \(numerator)/\(denominator)"
        }
    }

    /// Rounded to `digits` decimals, without a "-0".
    private static func signed(_ value: Double, digits: Int) -> String {
        let text = String(format: "%.\(digits)f", value)
        return Double(text) == 0 ? String(format: "%.\(digits)f", 0.0) : text
    }
}
