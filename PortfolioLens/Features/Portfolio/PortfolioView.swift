import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Environment(MarketStore.self) private var store
    @Environment(FXStore.self) private var fx
    @Query(sort: \ManualHolding.name) private var manualHoldings: [ManualHolding]
    @State private var isAddingHolding = false
    @State private var editingHolding: ManualHolding?

    private var brokerCurrency: String { store.account?.currency ?? "USD" }

    var body: some View {
        let manual = manualHoldings.map(\.snapshot)
        let summary = PortfolioCalculator.summary(account: store.account, positions: store.positions,
                                                  quotes: store.quotes, manual: manual, converter: fx.converter)
        let holdings = PortfolioCalculator.holdings(account: store.account, positions: store.positions,
                                                    quotes: store.quotes, manual: manual)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.isSimulated {
                        NoticeBanner(icon: "sparkles", text: "Demo mode: prices are simulated. Add free Alpaca paper-trading keys in Settings to use real market data.")
                    }
                    if let error = store.errorMessage {
                        NoticeBanner(icon: "exclamationmark.triangle.fill", text: error, tint: Theme.loss) {
                            store.errorMessage = nil
                        }
                    }
                    HeroCard(summary: summary, isLoading: store.account == nil && store.isRefreshing)
                    metrics(summary)
                    AllocationPreview(holdings: holdings, converter: fx.converter)
                    positionsSection
                    outsideHoldingsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Portfolio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ConnectionIndicator(state: store.connection) }
            }
            .refreshable { await store.refreshAll() }
            .navigationDestination(for: String.self) { SymbolDetailView(symbol: $0) }
            .sheet(isPresented: $isAddingHolding) { ManualHoldingEditor(holding: nil) }
            .sheet(item: $editingHolding) { ManualHoldingEditor(holding: $0) }
        }
    }

    private func metrics(_ summary: PortfolioSummary) -> some View {
        let code = summary.baseCurrency
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(title: "Cash", value: Format.currency(summary.cash, code: code))
            MetricTile(title: "Invested", value: Format.currency(summary.investedValue, code: code))
            MetricTile(
                title: "Unrealized P&L",
                value: Format.signedCurrency(summary.unrealizedPL, code: code),
                detail: summary.unrealizedPLPercent.map { Format.percent($0, signed: true) },
                tint: Theme.color(for: summary.unrealizedPL))
            MetricTile(
                title: "Buying power",
                value: summary.buyingPower.map { Format.currency($0, code: code) } ?? "—")
        }
    }

    @ViewBuilder
    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Positions", trailing: store.positions.isEmpty ? nil : "\(store.positions.count)")
            if store.positions.isEmpty {
                Card {
                    Label(store.isRefreshing ? "Loading positions…" : "No positions yet. Buy something from Markets.",
                          systemImage: "tray")
                        .foregroundStyle(.secondary)
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(store.positions) { position in
                            NavigationLink(value: position.symbol) {
                                PositionRow(position: position, quote: store.quotes[position.symbol], currency: brokerCurrency)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if position.id != store.positions.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                }
            }
        }
    }

    private var outsideHoldingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("Outside holdings")
                Button { isAddingHolding = true } label: {
                    Label("Add", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                }
            }
            if manualHoldings.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("See your whole net worth").font(.subheadline.weight(.semibold))
                        Text("Add Indian stocks, mutual funds, fixed deposits, gold or cash held elsewhere. The Lens then shows your real currency and sector exposure across everything.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(manualHoldings) { holding in
                            Button { editingHolding = holding } label: {
                                ManualHoldingRow(holding: holding, converter: fx.converter)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if holding.id != manualHoldings.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HeroCard: View {
    let summary: PortfolioSummary
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Net worth · \(summary.baseCurrency)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            if isLoading {
                ProgressView().tint(.white).frame(height: 46)
            } else {
                Text(Format.currency(summary.totalValue, code: summary.baseCurrency))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: summary.totalValue.doubleValue))
                    .animation(.snappy, value: summary.totalValue)
            }

            HStack(spacing: 6) {
                Image(systemName: summary.dayChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text(Format.signedCurrency(summary.dayChange, code: summary.baseCurrency))
                    .contentTransition(.numericText())
                if let percent = summary.dayChangePercent {
                    Text("(\(Format.percent(percent, signed: true)))")
                }
                Text("today").foregroundStyle(.white.opacity(0.7))
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.15), in: Capsule())

            if summary.manualValue != 0 {
                Text("Includes \(Format.currency(summary.manualValue, code: summary.baseCurrency)) held outside your broker")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if !summary.unconvertedCurrencies.isEmpty {
                Text("No exchange rate for \(summary.unconvertedCurrencies.joined(separator: ", ")); those assets are excluded.")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 8)
    }
}

private struct AllocationPreview: View {
    let holdings: [HoldingSnapshot]
    let converter: CurrencyConverter

    var body: some View {
        let slices = ExposureAnalyzer.slices(holdings, by: .sector, converter: converter, maxSlices: 5)
        if !slices.isEmpty {
            Card {
                HStack(spacing: 18) {
                    DonutChart(slices: slices, innerRatio: 0.6)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Allocation by sector").font(.subheadline.weight(.semibold))
                        ForEach(Array(slices.prefix(4).enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: 6) {
                                Circle().fill(Theme.paletteColor(index)).frame(width: 8, height: 8)
                                Text(slice.label).font(.caption).lineLimit(1)
                                Spacer()
                                Text(Format.percent(slice.weight)).font(.caption.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct PositionRow: View {
    let position: Position
    let quote: Quote?
    let currency: String

    var body: some View {
        let price = quote?.price ?? position.currentPrice
        let previous = quote?.previousClose ?? position.lastDayPrice
        let value = position.quantity * price
        let profit = position.quantity * (price - position.averageEntryPrice)
        let dayPercent: Decimal? = previous == 0 ? nil : (price - previous) / previous

        HStack(spacing: 12) {
            SymbolBadge(symbol: position.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(position.symbol).font(.headline)
                Text("\(Format.quantity(position.quantity)) @ \(Format.price(position.averageEntryPrice))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.currency(value, code: currency))
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value.doubleValue))
                    .animation(.snappy, value: value)
                HStack(spacing: 6) {
                    Text(Format.signedCurrency(profit, code: currency))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color(for: profit))
                    ChangePill(percent: dayPercent, style: .subtle)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
