import CoreBluetooth
import Foundation
import Observation
import os

struct DiscoveredPrinter: Identifiable, Hashable {
    let id: UUID
    let name: String
}

enum PrinterError: LocalizedError {
    case notConnected

    var errorDescription: String? { "The printer is not connected." }
}

/// The REEKON P1L over Bluetooth LE (SDK Section II). Finds printers, keeps the chosen one connected,
/// and prints labels through `PrintSender`.
@Observable
final class P1LPrinter: NSObject {
    enum State: Equatable {
        case off
        case unauthorized
        case idle
        case scanning
        case connecting(String)
        case connected(String)
        case printing(String)
    }

    private(set) var state = State.idle
    private(set) var discovered: [DiscoveredPrinter] = []
    private(set) var isCoolingDown = false
    private(set) var lastError: String?

    var isReady: Bool { if case .connected = state { true } else { false } }
    var printerName: String? {
        switch state {
        case .connecting(let name), .connected(let name), .printing(let name): name
        default: nil
        }
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var printCharacteristic: CBCharacteristic?
    @ObservationIgnored private var readyToWrite: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private lazy var sender = PrintSender(transport: self)

    // iOS reports the print service as 0xAE30; the SDK says to accept 0xAF30 too.
    private static let printServices = [CBUUID(string: "AE30"), CBUUID(string: "AF30")]
    private static let printCharacteristicID = CBUUID(string: "AE01")
    private static let savedPrinterKey = "printerIdentifier"
    private static let log = Logger(subsystem: "tools.reekon.labeler", category: "printer")

    private var savedPrinterID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.savedPrinterKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedPrinterKey) }
    }

    var hasSavedPrinter: Bool { savedPrinterID != nil }

    /// Creates the Bluetooth manager. Called at launch only when a printer is remembered, so the
    /// Bluetooth permission prompt appears when the user first asks for a printer.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        wantsScan = true
        activate()
        guard let central, central.state == .poweredOn else { return }
        discovered.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if peripheral == nil { state = .scanning }
        Self.log.info("Scanning for P1L printers")
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ id: UUID) {
        guard let central, let target = peripherals[id] else { return }
        stopScan()
        if let current = peripheral, current.identifier != id { central.cancelPeripheralConnection(current) }
        peripheral = target
        target.delegate = self
        state = .connecting(target.name ?? "P1L")
        central.connect(target)
    }

    func forget() {
        savedPrinterID = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        printCharacteristic = nil
        state = .idle
    }

    func print(_ document: LabelDocument) async {
        guard case .connected(let name) = state, !isCoolingDown else { return }
        state = .printing(name)
        lastError = nil
        let job = PrintJobEncoder.encode(PrintJobEncoder.headBitmap(for: document))
        do {
            try await sender.send(job, feedMM: document.size.feedMM)
            Self.log.info("Sent label: \(job.data.count) data bytes, \(document.size.displayName, privacy: .public)")
            if case .printing = state { state = .connected(name) }
            isCoolingDown = true
            try? await Task.sleep(for: PrintSender.cooldown(feedMM: document.size.feedMM))
            isCoolingDown = false
        } catch {
            Self.log.error("Print failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            if case .printing = state { state = .connected(name) }
        }
    }

    private func reconnectSaved() {
        guard let central, let id = savedPrinterID,
              let saved = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripherals[id] = saved
        connect(id)
    }

    private func didLoseConnection() {
        printCharacteristic = nil
        readyToWrite?.resume()
        readyToWrite = nil
    }
}

// MARK: - PrintTransport

extension P1LPrinter: PrintTransport {
    var maximumWriteLength: Int {
        peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? PrintSender.fallbackWriteLength
    }

    func writeWithoutResponse(_ bytes: [UInt8]) async throws {
        guard let peripheral, let printCharacteristic else { throw PrinterError.notConnected }
        if !peripheral.canSendWriteWithoutResponse {
            await withCheckedContinuation { readyToWrite = $0 }
            guard self.printCharacteristic != nil else { throw PrinterError.notConnected }
        }
        peripheral.writeValue(Data(bytes), for: printCharacteristic, type: .withoutResponse)
    }
}

// MARK: - CoreBluetooth delegates (main queue)

extension P1LPrinter: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.log.info("Bluetooth state \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if state == .off || state == .unauthorized { state = .idle }
            reconnectSaved()
            if wantsScan { startScan() }
        case .unauthorized:
            state = .unauthorized
        default:
            didLoseConnection()
            state = .off
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.contains("P1") else { return }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        // The SDK identifies the P1L by name and print service; accept a missing service list too, logged.
        guard services.map({ !Set($0).isDisjoint(with: Self.printServices) }) ?? true else {
            Self.log.info("Skipped \(name, privacy: .public): no print service in \(String(describing: services), privacy: .public)")
            return
        }
        peripherals[peripheral.identifier] = peripheral
        if !discovered.contains(where: { $0.id == peripheral.identifier }) {
            discovered.append(DiscoveredPrinter(id: peripheral.identifier, name: name))
            Self.log.info("Found \(name, privacy: .public) services=\(String(describing: services), privacy: .public)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Self.log.info("Connected to \(peripheral.name ?? "?", privacy: .public); discovering services")
        peripheral.discoverServices(Self.printServices)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Self.log.error("Connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        lastError = error?.localizedDescription ?? "Could not connect to the printer."
        state = .idle
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        Self.log.info("Disconnected: \(error?.localizedDescription ?? "by request", privacy: .public)")
        didLoseConnection()
        guard peripheral.identifier == self.peripheral?.identifier, savedPrinterID == peripheral.identifier else {
            state = .idle
            return
        }
        // Keep a pending connection so the printer reconnects when it is switched back on.
        state = .connecting(peripheral.name ?? "P1L")
        central.connect(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { Self.printServices.contains($0.uuid) }) else {
            Self.log.error("No print service on \(peripheral.name ?? "?", privacy: .public)")
            lastError = "This device has no P1L print service."
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.printCharacteristicID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.printCharacteristicID }) else {
            lastError = "This device has no P1L print characteristic."
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        printCharacteristic = characteristic
        savedPrinterID = peripheral.identifier
        state = .connected(peripheral.name ?? "P1L")
        Self.log.info("Ready; max write \(peripheral.maximumWriteValueLength(for: .withoutResponse))")
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        readyToWrite?.resume()
        readyToWrite = nil
    }
}
