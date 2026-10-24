import CoreBluetooth
import Foundation
import Observation
import os

/// A REEKON tool found nearby, as the tape sheet lists it.
struct NearbyTool: Identifiable, Hashable {
    let id: UUID
    let name: String
    let offer: T1Protocol.Offer
}

/// The T1 Tomahawk over Bluetooth LE (SDK Section I), with its own Bluetooth manager; the printer keeps its own.
/// Finds tools, connects the chosen T1, and reconnects it by device_id whenever it wakes and advertises (S18).
@Observable
final class T1Tape: NSObject {
    enum State: Equatable {
        case off
        case unauthorized
        case idle
        /// Scanning: for the sheet, or for the remembered tool, which advertises only while awake.
        case searching
        case connecting(String)
        case connected(String)
        /// No Sync Service: old firmware or recovery mode.
        case needsUpdate(String)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var nearby: [NearbyTool] = []
    /// Rebuilt on each connect: Request All sends every saved measurement again (S19).
    private(set) var measurements = MeasurementList()

    var toolName: String? {
        switch state {
        case .connecting(let name), .connected(let name): name
        default: nil
        }
    }
    var isConnected: Bool { if case .connected = state { true } else { false } }
    var hasSavedTool: Bool { savedDeviceID != nil }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var deviceIDs: [UUID: String] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var comm: CBCharacteristic?
    @ObservationIgnored private var sheetIsOpen = false

    private static let syncService = CBUUID(string: T1Protocol.syncService)
    private static let commID = CBUUID(string: T1Protocol.comm)
    private static let versionID = CBUUID(string: T1Protocol.protocolVersion)
    private static let savedDeviceKey = "tapeDeviceID"
    private static let savedPeripheralKey = "tapePeripheralIdentifier"
    private static let log = Logger(subsystem: "tools.reekon.labeler", category: "tape")

    /// The chosen tool, by its permanent device_id: its Bluetooth address, and so its identifier, can change.
    private var savedDeviceID: String? {
        get { UserDefaults.standard.string(forKey: Self.savedDeviceKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.savedDeviceKey) }
    }
    private var savedPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.savedPeripheralKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedPeripheralKey) }
    }

    /// Creates the Bluetooth manager. Called at launch only when a tool is remembered, so the Bluetooth
    /// permission prompt appears when the user first opens Tape.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// The sheet is open: list every REEKON tool in range.
    func sheetAppeared() {
        sheetIsOpen = true
        activate()
        nearby.removeAll()
        scan()
    }

    func sheetDisappeared() {
        sheetIsOpen = false
        scan()
    }

    func connect(_ id: UUID) {
        guard let central, let target = peripherals[id],
              case .tomahawk = nearby.first(where: { $0.id == id })?.offer else { return }
        if let current = peripheral, current.identifier != id { central.cancelPeripheralConnection(current) }
        peripheral = target
        target.delegate = self
        state = .connecting(name(of: target))
        Self.log.info("Connecting to \(self.name(of: target), privacy: .public)")
        central.connect(target)
        scan()
    }

    func forget() {
        savedDeviceID = nil
        savedPeripheralID = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        comm = nil
        state = .idle
        scan()
    }

    /// Scans while the sheet is open (with repeats, so a scan response that arrives after the advertising still
    /// updates the row) or while the remembered tool is not connected (without repeats, to save power).
    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        let waitingForSaved = hasSavedTool && !isConnected
        guard sheetIsOpen || waitingForSaved else {
            central.stopScan()
            if state == .searching { state = .idle }
            return
        }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: sheetIsOpen])
        if peripheral == nil, case .idle = state { state = .searching }
        if peripheral == nil, case .failed = state { state = .searching }
    }

    /// At launch or when Bluetooth comes on: a pending connection to the remembered tool, which completes when
    /// it wakes. A scan by device_id covers an address that changed.
    private func reconnectSaved() {
        guard let central, peripheral == nil, let id = savedPeripheralID,
              let saved = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = saved
        saved.delegate = self
        state = .connecting(name(of: saved))
        central.connect(saved)
    }

    private func name(of peripheral: CBPeripheral) -> String {
        nearby.first { $0.id == peripheral.identifier }?.name ?? T1Protocol.displayName(peripheral.name)
    }

    private func didLoseConnection() {
        comm = nil
    }
}

// MARK: - CoreBluetooth delegates (main queue)

extension T1Tape: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.log.info("Bluetooth state \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if state == .off || state == .unauthorized { state = .idle }
            reconnectSaved()
            scan()
        case .unauthorized:
            state = .unauthorized
        default:
            didLoseConnection()
            peripheral = nil
            state = .off
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        guard let offer = T1Protocol.offer(
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs: services, name: advertisedName) else { return }
        let tool = NearbyTool(id: peripheral.identifier, name: T1Protocol.displayName(advertisedName), offer: offer)
        peripherals[peripheral.identifier] = peripheral
        if let index = nearby.firstIndex(where: { $0.id == tool.id }) {
            if nearby[index] != tool { nearby[index] = tool }
        } else {
            nearby.append(tool)
            Self.log.info("Found \(tool.name, privacy: .public): \(String(describing: offer), privacy: .public)")
        }
        guard case .tomahawk(let advertisement) = offer else { return }
        deviceIDs[peripheral.identifier] = advertisement.deviceID
        // The remembered tool woke up: connect without the sheet, wherever its address now is.
        guard advertisement.deviceID == savedDeviceID else { return }
        if self.peripheral?.identifier == peripheral.identifier, case .connecting = state { return }
        if !isConnected {
            Self.log.info("Remembered tool \(advertisement.deviceID, privacy: .public) is advertising; reconnecting")
            if let pending = self.peripheral { central.cancelPeripheralConnection(pending) }
            self.peripheral = peripheral
            peripheral.delegate = self
            state = .connecting(tool.name)
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Self.log.info("Connected to \(self.name(of: peripheral), privacy: .public); discovering services")
        peripheral.discoverServices([Self.syncService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Self.log.error("Connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        // A cancelled attempt superseded by another tape (or the same tape at a new address) says nothing
        // about the current one.
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        self.peripheral = nil
        state = .failed(error?.localizedDescription ?? "Could not connect to the tape.")
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        Self.log.info("Disconnected: \(error?.localizedDescription ?? "by request", privacy: .public)")
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        didLoseConnection()
        if case .needsUpdate = state {
            self.peripheral = nil
            return
        }
        guard savedPeripheralID == peripheral.identifier else {
            self.peripheral = nil
            state = .idle
            scan()
            return
        }
        // The T1 sleeps about 3 minutes after its last use. Keep a pending connection so a button press
        // reconnects it, and scan in case it comes back at another address.
        state = .connecting(name(of: peripheral))
        central.connect(peripheral)
        scan()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.syncService }) else {
            Self.log.error("No Sync Service on \(self.name(of: peripheral), privacy: .public)")
            state = .needsUpdate(name(of: peripheral))
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.commID, Self.versionID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let comm = service.characteristics?.first(where: { $0.uuid == Self.commID }) else {
            Self.log.error("No Comm characteristic on \(self.name(of: peripheral), privacy: .public)")
            state = .needsUpdate(name(of: peripheral))
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        self.comm = comm
        if let version = service.characteristics?.first(where: { $0.uuid == Self.versionID }) {
            peripheral.readValue(for: version)
        }
        // Notify, never indicate: with indications the T1 sends nothing.
        peripheral.setNotifyValue(true, for: comm)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.commID else { return }
        guard characteristic.isNotifying, error == nil else {
            Self.log.error("Subscribe failed: \(error?.localizedDescription ?? "not notifying", privacy: .public)")
            state = .failed("The tape did not accept the connection. Press a button on it and try again.")
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        // Every saved measurement, then each new one the moment it is saved.
        measurements.removeAll()
        peripheral.writeValue(T1Protocol.message(opcode: T1Protocol.requestAllOpcode), for: characteristic,
                              type: .withResponse)
        savedPeripheralID = peripheral.identifier
        if let deviceID = deviceIDs[peripheral.identifier] { savedDeviceID = deviceID }
        state = .connected(name(of: peripheral))
        scan()
        Self.log.info("Ready; requested all measurements, max write \(peripheral.maximumWriteValueLength(for: .withResponse))")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { Self.log.error("Write failed: \(error.localizedDescription, privacy: .public)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        if characteristic.uuid == Self.commID {
            let deviceID = deviceIDs[peripheral.identifier] ?? savedDeviceID ?? peripheral.identifier.uuidString
            // Other opcodes (newer firmware, items from a T1M) are ignored.
            guard let measurement = T1Protocol.measurement(from: value, deviceID: deviceID) else { return }
            let isNew = measurements.add(measurement)
            Self.log.info("""
                Measurement \(measurement.letter, privacy: .public) \(measurement.positionUM) µm \
                uuid \(measurement.uuid) flags \(measurement.flags)\(isNew ? "" : " (repeat)", privacy: .public)
                """)
        } else if characteristic.uuid == Self.versionID {
            let version = value.count >= 4 ? value.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } : 0
            Self.log.info("Protocol version \(UInt32(littleEndian: version))")
        }
    }
}
