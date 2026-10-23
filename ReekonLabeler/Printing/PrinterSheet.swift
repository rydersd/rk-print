import SwiftUI

/// Finds and connects a P1L. The connected printer is remembered and reconnects on launch.
struct PrinterSheet: View {
    let printer: P1LPrinter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Status", value: status)
                    if let error = printer.lastError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    if printer.printerName != nil {
                        Button("Forget Printer", role: .destructive) { printer.forget() }
                    }
                }
                Section {
                    ForEach(printer.discovered) { found in
                        Button {
                            printer.connect(found.id)
                        } label: {
                            HStack {
                                Text(found.name).foregroundStyle(.primary)
                                Spacer()
                                if printer.printerName == found.name { stateBadge }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby")
                        if printer.state == .scanning { ProgressView().controlSize(.small) }
                    }
                } footer: {
                    Text("Turn the P1L on. It doesn't need pairing in Settings.")
                }
            }
            .navigationTitle("Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { printer.startScan() }
            .onDisappear { printer.stopScan() }
            .onChange(of: printer.isReady) { _, ready in if ready { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private var status: String {
        switch printer.state {
        case .off: "Bluetooth is off"
        case .unauthorized: "Bluetooth not allowed. Turn it on in Settings."
        case .idle: "Not connected"
        case .scanning: "Searching…"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): "Connected to \(name)"
        case .printing(let name): "Printing on \(name)…"
        }
    }

    @ViewBuilder private var stateBadge: some View {
        if printer.isReady { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        else { ProgressView().controlSize(.small) }
    }
}
