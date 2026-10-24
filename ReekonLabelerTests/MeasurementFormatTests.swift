import Testing
@testable import Labeler

struct MeasurementFormatTests {
    @Test func formatsEachUnit() {
        let reading: Int32 = 644_525
        #expect(MeasurementFormat.format(positionUM: reading, unit: .fractionalInches) == "25 3/8\"")
        #expect(MeasurementFormat.format(positionUM: reading, unit: .feetInches) == "2' 1 3/8\"")
        #expect(MeasurementFormat.format(positionUM: reading, unit: .millimetres) == "645 mm")
        #expect(MeasurementFormat.format(positionUM: reading, unit: .centimetres) == "64.5 cm")
        #expect(MeasurementFormat.format(positionUM: -12_700, unit: .fractionalInches) == "-1/2\"")
        // 15/16 and a bit rounds up to the next inch.
        #expect(MeasurementFormat.format(positionUM: 25_390, unit: .fractionalInches) == "1\"")
    }
}
