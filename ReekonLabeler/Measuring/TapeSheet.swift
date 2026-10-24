import SwiftUI

/// Connects the T1 Tomahawk (S18). The chosen tape is remembered and reconnects whenever it wakes.
struct TapeSheet: View {
    let tape: T1Tape
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
            }
            .navigationTitle("Tape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
