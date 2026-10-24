import Foundation
import Testing
@testable import Labeler

struct MeasurementListTests {
    private func measurement(_ uuid: UInt32, deviceID: String = "a102030405060708") -> T1Measurement {
        T1Protocol.measurement(from: T1ProtocolTests.legacyMessage(uuid: uuid, positionUM: Int32(uuid) * 1000),
                               deviceID: deviceID)!
    }

    @Test func dropsRepeats() {
        var list = MeasurementList()
        let added = [list.add(measurement(1)), list.add(measurement(2)), list.add(measurement(1)),
                     list.add(measurement(1, deviceID: "ffffffffffffffff"))]
        #expect(added == [true, true, false, true])
        #expect(list.entries.map(\.uuid) == [1, 2, 1])
        #expect(list.entries.map(\.deviceID) == ["ffffffffffffffff", "a102030405060708", "a102030405060708"])
    }
}
