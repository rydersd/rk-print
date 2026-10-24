import SwiftUI

/// Connects the T1 Tomahawk (S18), lists its measurements (S19) and inserts the ticked ones as a table (S21).
/// The chosen tape is remembered and reconnects whenever it wakes.
struct TapeSheet: View {
    let tape: T1Tape
    /// Adds the table to the label; one Undo removes it.
    let insertTable: (TableContent) -> Void
    @AppStorage("measurementUnit") private var unit = MeasurementUnit.fractionalInches
    /// Ticked measurement ids, in the order ticked: that is the order of the rows.
    @State private var picked: [T1Measurement.ID] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Status", value: status)
                        .accessibilityIdentifier("tapeStatus")
                    if tape.hasSavedTool {
                        Button("Forget Tape", role: .destructive) { tape.forget() }
                    }
                }
                if !tape.isConnected { nearbySection }
                measurementsSection
            }
            .navigationTitle("Tape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert Table") {
                        insertTable(TableContent.fromMeasurements(pickedMeasurements, unit: unit))
                        dismiss()
                    }
                    .disabled(pickedMeasurements.isEmpty)
                    .accessibilityIdentifier("insertMeasurements")
                }
            }
            .onAppear { tape.sheetAppeared() }
            .onDisappear { tape.sheetDisappeared() }
        }
        .presentationDetents([.medium, .large])
    }

    private var nearbySection: some View {
        Section {
            ForEach(tape.nearby) { tool in
                Button {
                    tape.connect(tool.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tool.name).foregroundStyle(isConnectable(tool) ? .primary : .secondary)
                            if let note = note(for: tool) { Text(note).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if tape.toolName == tool.name { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(!isConnectable(tool))
            }
        } header: {
            HStack {
                Text("Nearby")
                if tape.state == .searching { ProgressView().controlSize(.small) }
            }
        } footer: {
            Text("Press a button on the T1 to wake it. It doesn't need pairing in Settings.")
        }
    }

    private var measurementsSection: some View {
        Section {
            Picker("Unit", selection: $unit) {
                ForEach(MeasurementUnit.allCases) { Text($0.title).tag($0) }
            }
            ForEach(tape.measurements.entries) { measurement in
                Button { toggle(measurement.id) } label: {
                    HStack {
                        Image(systemName: picked.contains(measurement.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(measurement.id) ? Theme.selection : .secondary)
                        Text(measurement.letter).foregroundStyle(.secondary)
                        Spacer()
                        Text(MeasurementFormat.format(positionUM: measurement.positionUM, unit: unit))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(picked.contains(measurement.id) ? .isSelected : [])
            }
        } header: {
            Text("Measurements")
        } footer: {
            if tape.measurements.entries.isEmpty {
                Text(tape.isConnected ? "Save a measurement on the T1 and it appears here."
                                      : "Connect your T1 to see the measurements saved on it.")
            } else {
                Text("Tick measurements in the order you want them as rows.")
            }
        }
    }

    /// Ticked measurements still in the list (a reconnect rebuilds it), in the order ticked.
    private var pickedMeasurements: [T1Measurement] {
        picked.compactMap { id in tape.measurements.entries.first { $0.id == id } }
    }

    private func toggle(_ id: T1Measurement.ID) {
        if let index = picked.firstIndex(of: id) { picked.remove(at: index) } else { picked.append(id) }
    }

    private func isConnectable(_ tool: NearbyTool) -> Bool {
        if case .tomahawk = tool.offer { true } else { false }
    }

    private func note(for tool: NearbyTool) -> String? {
        switch tool.offer {
        case .tomahawk: nil
        case .notSupported: "Not supported yet"
        case .keyboardMode: "In Keyboard mode: switch it to APP mode in its Bluetooth menu"
        }
    }

    private var status: String {
        switch tape.state {
        case .off: "Bluetooth is off"
        case .unauthorized: "Bluetooth not allowed. Turn it on in Settings."
        case .idle: "Not connected"
        case .searching: tape.hasSavedTool ? "Waiting for your T1. Press a button on it." : "Searching…"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): "Connected to \(name)"
        case .needsUpdate(let name): "\(name) needs a firmware update in REEKON's app."
        case .failed(let message): message
        }
    }
}
