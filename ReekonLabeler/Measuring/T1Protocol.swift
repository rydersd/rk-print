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

    static let legacyMeasurementOpcode: UInt32 = 4
    static let requestAllOpcode: UInt32 = 7

    /// A Comm notification as a measurement, or nil for another opcode or a message too short. The T1 sends
    /// every measurement as a 24-byte Legacy Measurement (Figure 6).
    static func measurement(from message: Data, deviceID: String) -> T1Measurement? {
        let bytes = Array(message)
        guard bytes.count >= 8, uint32(bytes, at: 0) == legacyMeasurementOpcode else { return nil }
        let data = Array(bytes.dropFirst(8).prefix(Int(uint32(bytes, at: 4))))
        guard data.count >= 24 else { return nil }
        return T1Measurement(deviceID: deviceID, uuid: uint32(data, at: 0), flags: uint32(data, at: 4),
                             positionUM: Int32(bitPattern: uint32(data, at: 8)),
                             group: uint16(data, at: 20), number: uint16(data, at: 22))
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

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

/// One measurement saved on a tool (S19), identified by the tool's device_id and its uuid.
nonisolated struct T1Measurement: Hashable, Sendable, Identifiable {
    let deviceID: String
    let uuid: UInt32
    let flags: UInt32
    /// The value the tool showed, in µm; negative in relative mode.
    let positionUM: Int32
    /// 0 is DEFAULT, n is GROUP n+1.
    let group: UInt16
    /// 0 = A, 1 = B …
    let number: UInt16

    var id: String { "\(deviceID)-\(uuid)" }

    /// As the tool shows it: "A", or "Group 2 · B".
    var letter: String {
        var letters = "", n = Int(number)
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + n % 26))) + letters
            n = n / 26 - 1
        } while n >= 0
        return group == 0 ? letters : "Group \(Int(group) + 1) · \(letters)"
    }
}
