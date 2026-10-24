import Foundation
import Testing
@testable import Labeler

struct T1ProtocolTests {
    /// The scan response's manufacturer data: company 0x0DF4 as F4 0D, device_type, then device_id little-endian.
    private func manufacturerData(type: UInt8, id: [UInt8] = [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0xA1],
                                  company: [UInt8] = [0xF4, 0x0D]) -> Data {
        Data(company + [type] + id)
    }

    @Test func recognisesTomahawkAdvertising() {
        let tool = T1Protocol.advertisement(manufacturerData: manufacturerData(type: 1))
        #expect(tool == T1Protocol.Advertisement(deviceType: 1, deviceID: "a102030405060708"))
        #expect(tool?.isTomahawk == true)
        #expect(T1Protocol.advertisement(manufacturerData: manufacturerData(type: 1, company: [0x4C, 0x00])) == nil)
        #expect(T1Protocol.advertisement(manufacturerData: Data([0xF4, 0x0D, 0x01, 0x02])) == nil)
        #expect(T1Protocol.advertisement(manufacturerData: nil) == nil)

        #expect(T1Protocol.offer(manufacturerData: manufacturerData(type: 1), serviceUUIDs: ["180F"],
                                 name: "REEKON T1") == .tomahawk(tool!))
        let utility = T1Protocol.offer(manufacturerData: manufacturerData(type: 2), serviceUUIDs: [], name: "REEKON T1M")
        #expect(utility == .notSupported(T1Protocol.Advertisement(deviceType: 2, deviceID: "a102030405060708")))
    }

    @Test func skipsKeyboardMode() {
        let data = manufacturerData(type: 1)
        #expect(T1Protocol.offer(manufacturerData: data, serviceUUIDs: ["180F", "1812"], name: "REEKON T1")
                == .keyboardMode)
        #expect(T1Protocol.offer(manufacturerData: data, serviceUUIDs: ["180F"], name: "REEKON T1 [HID]")
                == .keyboardMode)
        // The T1M and T1R send no scan response in Keyboard mode: the name alone says what it is.
        #expect(T1Protocol.offer(manufacturerData: nil, serviceUUIDs: ["1812"], name: "REEKON T1M [HID]")
                == .keyboardMode)
        // Not a REEKON tool at all.
        #expect(T1Protocol.offer(manufacturerData: nil, serviceUUIDs: ["1812"], name: "Magic Keyboard") == nil)
    }

    /// A Legacy Measurement message (opcode 4, Figure 6): header, then 24 bytes of data.
    static func legacyMessage(uuid: UInt32, positionUM: Int32, group: UInt16 = 0, number: UInt16 = 0,
                              opcode: UInt32 = 4, dataLength: Int = 24) -> Data {
        func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }
        var data = bytes(uuid) + bytes(UInt32(1)) + bytes(positionUM) + bytes(Int32(0)) + bytes(Int32(0))
        data += bytes(group) + bytes(number)
        data = Array(data.prefix(dataLength))
        return Data(bytes(opcode) + bytes(UInt32(data.count)) + data)
    }

    @Test func parsesLegacyMeasurement() throws {
        let message = Self.legacyMessage(uuid: 0x0102_0304, positionUM: 644_525, group: 1, number: 1)
        let measurement = try #require(T1Protocol.measurement(from: message, deviceID: "a102030405060708"))
        #expect(measurement.uuid == 0x0102_0304)
        #expect(measurement.positionUM == 644_525)
        #expect(measurement.group == 1)
        #expect(measurement.number == 1)
        #expect(measurement.letter == "Group 2 · B")
        #expect(T1Protocol.measurement(from: Self.legacyMessage(uuid: 9, positionUM: -12_700), deviceID: "x")?
            .letter == "A")

        #expect(T1Protocol.measurement(from: Self.legacyMessage(uuid: 1, positionUM: 5, dataLength: 20),
                                       deviceID: "x") == nil)
        #expect(T1Protocol.measurement(from: Self.legacyMessage(uuid: 1, positionUM: 5, opcode: 13),
                                       deviceID: "x") == nil)
        #expect(T1Protocol.measurement(from: Data([4, 0, 0]), deviceID: "x") == nil)
    }
}
