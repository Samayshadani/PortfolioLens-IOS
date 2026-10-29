import SwiftUI
import SwiftData

struct WatchlistView: View {
    @Environment(MarketStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchlistItem.sortIndex) private var items: [WatchlistItem]
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if store.isSimulated {
                    Section {
                        NoticeBanner(icon: "sparkles", text: "Simulated prices. Real quotes need Alpaca keys and stream during US market hours (7:00 PM – 1:30 AM IST).")
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    ForEach(items) { item in
                        NavigationLink(value: item.symbol) {
                            WatchlistRow(item: item, quote: store.quotes[item.symbol])
                        }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Your watchlist is empty", systemImage: "star",
                                           description: Text("Tap + to add a stock or ETF."))
                }
            }
            .navigationTitle("Markets")
            .navigationDestination(for: String.self) { SymbolDetailView(symbol: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add symbol")
                }
            }
            .refreshable { await store.refreshAll() }
            .sheet(isPresented: $isAdding) {
                AddSymbolSheet(existing: Set(items.map(\.symbol)), nextIndex: (items.map(\.sortIndex).max() ?? -1) + 1)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(items[index]) }
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() { item.sortIndex = index }
        try? context.save()
    }
}

private struct WatchlistRow: View {
    let item: WatchlistItem
    let quote: Quote?

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: item.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.symbol).font(.headline)
                Text(item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 4) {
                    LivePriceText(value: quote.price, font: .headline)
                    ChangePill(percent: quote.changePercent)
                }
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddSymbolSheet: View {
    let existing: Set<String>
    let nextIndex: Int
    @Environment(MarketStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var result: AssetInfo?
    @State private var errorMessage: String?
    @State private var isSearching = false

    private let suggestions = ["NFLX", "META", "AMD", "IBKR", "JPM", "V", "COST", "QQQ", "VOO", "INDA", "GLD", "INFY"]

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ticker, e.g. NFLX", text: $query)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                } footer: {
                    Text("Alpaca's free plan covers US-listed stocks and ETFs.")
                }

                if isSearching {
                    Section { HStack { ProgressView(); Text("Looking up \(normalizedQuery)…").foregroundStyle(.secondary) } }
                } else if let result {
                    Section("Result") {
                        HStack(spacing: 12) {
                            SymbolBadge(symbol: result.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.symbol).font(.headline)
                                Text("\(result.name) · \(result.exchange)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if existing.contains(result.symbol) {
                                Text("Added").foregroundStyle(.secondary)
                            } else {
                                Button("Add") { add(result.symbol, name: result.name) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!result.tradable)
                            }
                        }
                    }
                } else if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }

                Section("Popular") {
                    ForEach(suggestions.filter { !existing.contains($0) }, id: \.self) { symbol in
                        Button { add(symbol, name: SectorDirectory.info(for: symbol).name) } label: {
                            HStack(spacing: 12) {
                                SymbolBadge(symbol: symbol, size: 32)
                                VStack(alignment: .leading) {
                                    Text(symbol).font(.subheadline.weight(.semibold))
                                    Text(SectorDirectory.info(for: symbol).name).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task(id: normalizedQuery) { await lookup() }
        }
        .presentationDetents([.medium, .large])
    }

    /// Debounced: the task is cancelled and restarted on every keystroke.
    private func lookup() async {
        result = nil
        errorMessage = nil
        let symbol = normalizedQuery
        guard !symbol.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let asset = try await store.lookupAsset(symbol)
            guard !Task.isCancelled else { return }
            result = asset
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ symbol: String, name: String) {
        guard !existing.contains(symbol) else { return }
        context.insert(WatchlistItem(symbol: symbol, name: name, sortIndex: nextIndex))
        try? context.save()
        dismiss()
    }
}
