import Testing
@testable import Labeler

struct TableContentTests {
    private func measurements(_ microns: [Int32]) -> [T1Measurement] {
        microns.enumerated().map { index, um in
            T1Measurement(deviceID: "a1", uuid: UInt32(index), flags: 0, positionUM: um, group: 0,
                          number: UInt16(index))
        }
    }

    @Test func threeMeasurementsAreLWD() {
        let three = TableContent.fromMeasurements(measurements([644_525, 304_800, 12_700]), unit: .fractionalInches)
        #expect(three.title == "")
        #expect(three.rows == [TableRow(label: "L", value: "25 3/8\""), TableRow(label: "W", value: "12\""),
                               TableRow(label: "D", value: "1/2\"")])
        let two = TableContent.fromMeasurements(measurements([644_525, 304_800]), unit: .millimetres)
        #expect(two.rows == [TableRow(label: "L", value: "645 mm"), TableRow(label: "W", value: "305 mm")])
    }

    @Test func otherCountsHaveBlankLabels() {
        let one = TableContent.fromMeasurements(measurements([644_525]), unit: .fractionalInches)
        #expect(one.rows == [TableRow(label: "", value: "25 3/8\""), TableRow()])
        let four = TableContent.fromMeasurements(measurements([1, 2, 3, 4].map { $0 * 25_400 }), unit: .fractionalInches)
        #expect(four.rows.map(\.label) == ["", "", "", ""])
        #expect(four.rows.map(\.value) == ["1\"", "2\"", "3\"", "4\""])
    }
}
