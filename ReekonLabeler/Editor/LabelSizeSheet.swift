import SwiftUI

/// Picks the loaded roll: its size, and its colour for the preview (S16). The P1L does not report its
/// stock (SDK Section II), so the user says.
struct LabelSizeSheet: View {
    let current: LabelSize
    let choose: (LabelSize) -> Void
    @State private var stock: LabelStock
    let chooseStock: (LabelStock) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var feedMM: Double
    @State private var headMM: Double

    init(current: LabelSize, stock: LabelStock, choose: @escaping (LabelSize) -> Void,
         chooseStock: @escaping (LabelStock) -> Void) {
        self.current = current
        self.choose = choose
        _stock = State(initialValue: stock)
        self.chooseStock = chooseStock
        _feedMM = State(initialValue: current.feedMM)
        _headMM = State(initialValue: current.headMM)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Colour") {
                    Picker("Colour", selection: $stock) {
                        ForEach(LabelStock.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("stockPicker")
                    .onChange(of: stock) { _, stock in chooseStock(stock) }
                }
                Section {
                    ForEach(LabelSize.presets, id: \.self) { size in
                        Button {
                            choose(size)
                            dismiss()
                        } label: {
                            HStack {
                                Text(size.displayName).foregroundStyle(.primary)
                                Spacer()
                                if size == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } header: {
                    Text("Size")
                } footer: {
                    Text("The printer can't tell the app which roll is loaded, so choose it here.")
                }
                Section("Custom") {
                    LabeledContent("Length (feed)") {
                        TextField("mm", value: $feedMM, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Width (across head)") {
                        TextField("mm", value: $headMM, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Button("Use \(LabelSize.custom(headMM: headMM, feedMM: feedMM).displayName)") {
                        choose(.custom(headMM: headMM, feedMM: feedMM))
                        dismiss()
                    }
                }
            }
            .navigationTitle("Label Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
