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
}
