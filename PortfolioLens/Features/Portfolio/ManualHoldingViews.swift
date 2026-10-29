import SwiftUI
import SwiftData

struct ManualHoldingRow: View {
    let holding: ManualHolding
    let converter: CurrencyConverter

    var body: some View {
        let converted = converter.convert(holding.marketValue, from: holding.currencyCode)
        HStack(spacing: 12) {
            SymbolBadge(symbol: holding.symbol.isEmpty ? holding.name : holding.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(holding.name).font(.headline).lineLimit(1)
                Text("\(holding.assetClass.title) · \(holding.sector)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.currency(holding.marketValue, code: holding.currencyCode))
                    .font(.headline)
                    .monospacedDigit()
                if let converted, holding.currencyCode != converter.base {
                    Text("≈ \(Format.currency(converted, code: converter.base))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct ManualHoldingEditor: View {
    let holding: ManualHolding?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var quantityText: String
    @State private var priceText: String
    @State private var currency: String
    @State private var sector: String
    @State private var assetClass: AssetClass

    init(holding: ManualHolding?) {
        self.holding = holding
        _name = State(initialValue: holding?.name ?? "")
        _symbol = State(initialValue: holding?.symbol ?? "")
        _quantityText = State(initialValue: holding.map { Format.plainNumber($0.quantity) } ?? "")
        _priceText = State(initialValue: holding.map { Format.plainNumber($0.unitPrice) } ?? "")
        _currency = State(initialValue: holding?.currencyCode ?? "INR")
        _sector = State(initialValue: holding?.sector ?? "Broad Market")
        _assetClass = State(initialValue: holding?.assetClass ?? .equity)
    }

    private var quantity: Decimal? { Decimal.parseUserInput(quantityText) }
    private var unitPrice: Decimal? { Decimal.parseUserInput(priceText) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        guard !trimmedName.isEmpty, let quantity, quantity > 0, let unitPrice, unitPrice >= 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset") {
                    TextField("Name, e.g. HDFC Flexi Cap Fund", text: $name)
                    TextField("Ticker (optional)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Type", selection: $assetClass) {
                        ForEach(AssetClass.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Sector", selection: $sector) {
                        ForEach(SectorDirectory.commonSectors, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    LabeledContent(assetClass == .cash ? "Amount" : "Quantity") {
                        TextField("0", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if assetClass != .cash {
                        LabeledContent("Price per unit") {
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(FXStore.supportedCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                    if let quantity, let unitPrice {
                        LabeledContent("Total value", value: Format.currency(quantity * unitPrice, code: currency))
                    }
                } header: {
                    Text("Value")
                } footer: {
                    Text("Update the price from time to time. Outside holdings aren't streamed live.")
                }
                if holding != nil {
                    Section {
                        Button("Delete holding", role: .destructive, action: delete)
                    }
                }
            }
            .navigationTitle(holding == nil ? "Add holding" : "Edit holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isValid) }
            }
            .onChange(of: assetClass) { _, newValue in
                if newValue == .cash {
                    sector = "Cash"
                    priceText = "1"
                }
            }
        }
    }

    private func save() {
        guard let quantity, let unitPrice else { return }
        let ticker = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        if let holding {
            holding.name = trimmedName
            holding.symbol = ticker
            holding.quantity = quantity
            holding.unitPrice = unitPrice
            holding.currencyCode = currency
            holding.sector = sector
            holding.assetClass = assetClass
            holding.updatedAt = .now
        } else {
            context.insert(ManualHolding(name: trimmedName, symbol: ticker, quantity: quantity, unitPrice: unitPrice,
                                         currencyCode: currency, sector: sector, assetClass: assetClass))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let holding { context.delete(holding) }
        try? context.save()
        dismiss()
    }
}

struct ManualHoldingsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXStore.self) private var fx
    @Query(sort: \ManualHolding.name) private var holdings: [ManualHolding]
    @State private var isAdding = false
    @State private var editing: ManualHolding?

    var body: some View {
        List {
            Section {
                ForEach(holdings) { holding in
                    Button { editing = holding } label: {
                        ManualHoldingRow(holding: holding, converter: fx.converter)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(holdings[index]) }
                    try? context.save()
                }
            } footer: {
                if !holdings.isEmpty {
                    Text("These are stored only on this device with SwiftData.")
                }
            }
        }
        .overlay {
            if holdings.isEmpty {
                ContentUnavailableView("No outside holdings", systemImage: "building.columns",
                                       description: Text("Add assets held outside your broker to see your true exposure."))
            }
        }
        .navigationTitle("Outside holdings")
        .toolbar {
            Button { isAdding = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add holding")
        }
        .sheet(isPresented: $isAdding) { ManualHoldingEditor(holding: nil) }
        .sheet(item: $editing) { ManualHoldingEditor(holding: $0) }
    }
}
