import Foundation

/// The REEKON measuring tools' Bluetooth data (SDK Section I), as plain bytes so it is unit-tested without
/// CoreBluetooth. Every number on the wire is little-endian.
nonisolated enum T1Protocol {
    /// REEKON's company ID 0x0DF4, as it starts the manufacturer data.
    static let companyID: [UInt8] = [0xF4, 0x0D]
    static let syncService = "43744f76-de4d-4b05-a14a-0c133a785d8e"
    static let comm = "6f0b2d1e-99e2-4ef4-bfab-70a5f3890f32"
    static let protocolVersion = "2731f0a6-c56c-4da8-85bd-a586145ad952"
    /// Keyboard mode adds the HID service; such a tool types its measurements and sends apps nothing.
    static let hidService = "1812"

    /// What a tool's scan response says about it (Figure 1).
    struct Advertisement: Hashable, Sendable {
        /// 1 T1 Tomahawk, 2 and 3 T1M, 5 T1R (Figure 2).
        let deviceType: UInt8
        /// The tool's permanent id as 16 lowercase hex digits, most significant byte first.
        let deviceID: String

        var isTomahawk: Bool { deviceType == 1 }
    }

    /// How a tool in range is offered in the tape sheet (S18).
    enum Offer: Hashable, Sendable {
        case tomahawk(Advertisement)
        /// The T1M and T1R: recognised, not supported yet.
        case notSupported(Advertisement)
        /// Switch it to APP mode in the tool's Bluetooth menu.
        case keyboardMode
    }

    /// The device type and id from manufacturer data as iOS reports it (company ID first), or nil for another
    /// company's device or data too short.
    static func advertisement(manufacturerData: Data?) -> Advertisement? {
        guard let bytes = manufacturerData.map(Array.init), bytes.count >= 11,
              Array(bytes[0..<2]) == companyID else { return nil }
        let id = bytes[3..<11].reversed().map { String(format: "%02x", $0) }.joined()
        return Advertisement(deviceType: bytes[2], deviceID: id)
    }

    /// How to offer what a scan found, or nil when it is not a REEKON tool.
    static func offer(manufacturerData: Data?, serviceUUIDs: [String], name: String?) -> Offer? {
        let named = name?.trimmingCharacters(in: .whitespaces).hasSuffix("[HID]") == true
        let hid = serviceUUIDs.contains { $0.caseInsensitiveCompare(hidService) == .orderedSame }
        guard let tool = advertisement(manufacturerData: manufacturerData) else {
            // The T1M and T1R send no scan response in Keyboard mode; their name still ends "[HID]".
            return named ? .keyboardMode : nil
        }
        if named || hid { return .keyboardMode }
        return tool.isTomahawk ? .tomahawk(tool) : .notSupported(tool)
    }

    /// The tool's name from advertising: always 16 bytes, padded with 0x00 when shorter.
    static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
        return trimmed.isEmpty ? "REEKON T1" : trimmed
    }

    // MARK: Comm messages (Figure 4)

    static let requestAllOpcode: UInt32 = 7

    /// One message for Comm: opcode, data length, data.
    static func message(opcode: UInt32, data: [UInt8] = []) -> Data {
        var bytes = littleEndian(opcode) + littleEndian(UInt32(data.count))
        bytes += data
        return Data(bytes)
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
