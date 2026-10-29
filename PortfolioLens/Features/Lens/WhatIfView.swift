import SwiftUI
import SwiftData

struct WhatIfView: View {
    @Environment(MarketStore.self) private var store
    @Environment(FXStore.self) private var fx
    @Query private var manualHoldings: [ManualHolding]
    @State private var symbolText: String
    @State private var side: OrderSide
    @State private var quantityText: String
    @State private var customPriceText = ""
    @State private var useMarketPrice = true
    @State private var isLoadingQuote = false
    @State private var isShowingTicket = false
    private let showsOrderButton: Bool

    init(initialSymbol: String = "", side: OrderSide = .buy, quantity: Decimal? = nil, showsOrderButton: Bool = true) {
        _symbolText = State(initialValue: initialSymbol)
        _side = State(initialValue: side)
        _quantityText = State(initialValue: quantity.map(Format.plainNumber) ?? "")
        self.showsOrderButton = showsOrderButton
    }

    private var symbol: String { symbolText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var quantity: Decimal? { Decimal.parseUserInput(quantityText) }
    private var marketPrice: Decimal? { store.quotes[symbol]?.price }
    private var price: Decimal? { useMarketPrice ? marketPrice : Decimal.parseUserInput(customPriceText) }
    private var currency: String { store.account?.currency ?? "USD" }

    private var result: WhatIfResult? {
        guard !symbol.isEmpty, let quantity, quantity > 0, let price, price > 0 else { return nil }
        let holdings = PortfolioCalculator.holdings(account: store.account, positions: store.positions,
                                                    quotes: store.quotes, manual: manualHoldings.map(\.snapshot))
        let trade = ProposedTrade(symbol: symbol, side: side, quantity: quantity, price: price, currency: currency)
        return WhatIfSimulator.simulate(holdings: holdings, trade: trade,
                                        buyingPower: store.account?.buyingPower, converter: fx.converter)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                inputCard
                if let result {
                    WhatIfResultView(result: result, currency: currency)
                    if showsOrderButton {
                        Button { isShowingTicket = true } label: {
                            Text("Continue to order ticket").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .controlSize(.large)
                        .tint(side == .buy ? Theme.gain : Theme.loss)
                    }
                } else {
                    placeholder
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.2), value: result)
        .task(id: symbol) { await loadQuote() }
        .sheet(isPresented: $isShowingTicket) {
            OrderTicketView(symbol: symbol, side: side, quantity: quantity)
        }
    }

    private var inputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Try a trade before you place it").font(.headline)
                HStack(spacing: 12) {
                    InputField(title: "Symbol", placeholder: "AAPL", text: $symbolText, capitalization: .characters)
                    InputField(title: "Quantity", placeholder: "10", text: $quantityText, keyboard: .decimalPad)
                }
                Picker("Side", selection: $side) {
                    ForEach(OrderSide.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $useMarketPrice) {
                    HStack(spacing: 6) {
                        Text("Use market price").font(.subheadline)
                        if useMarketPrice {
                            if let marketPrice {
                                LivePriceText(value: marketPrice, font: .subheadline.weight(.semibold))
                            } else if isLoadingQuote {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                }
                if !useMarketPrice {
                    InputField(title: "Assumed price", placeholder: "0.00", text: $customPriceText, keyboard: .decimalPad)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text("Enter a symbol and quantity").font(.headline)
            Text("You'll see how the trade changes your concentration, sectors, cash and diversification before any money moves.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !symbol.isEmpty, useMarketPrice, marketPrice == nil, !isLoadingQuote {
                Text("No price found for \(symbol).").font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal)
    }

    private func loadQuote() async {
        guard !symbol.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        isLoadingQuote = true
        _ = await store.quote(for: symbol)
        isLoadingQuote = false
    }
}

private struct WhatIfResultView: View {
    let result: WhatIfResult
    let currency: String

    var body: some View {
        VStack(spacing: 16) {
            verdict
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ImpactTile(title: "\(result.trade.symbol) weight",
                           before: Format.percent(result.positionWeightBefore),
                           after: Format.percent(result.positionWeightAfter),
                           tint: result.positionWeightAfter > WhatIfSimulator.concentrationLimit ? .orange : .primary)
                ImpactTile(title: "Shares",
                           before: Format.quantity(result.sharesBefore),
                           after: Format.quantity(result.sharesAfter))
                ImpactTile(title: "Cash",
                           before: Format.currency(result.cashBefore, code: currency),
                           after: Format.currency(result.cashAfter, code: currency),
                           tint: result.cashAfter < 0 ? Theme.loss : .primary)
                ImpactTile(title: "Diversification",
                           before: result.effectiveHoldingsBefore.map { Format.quantity($0.rounded(scale: 1)) } ?? "—",
                           after: result.effectiveHoldingsAfter.map { Format.quantity($0.rounded(scale: 1)) } ?? "—",
                           tint: diversificationTint)
            }

            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Heads up")
                    ForEach(result.warnings, id: \.self) { warning in
                        InsightCard(insight: RiskInsight(id: warning, severity: .caution, title: warning, detail: ""))
                    }
                }
            }

            changeCard(title: "Sector exposure", changes: result.sectorChanges)
            if result.currencyChanges.count > 1 {
                changeCard(title: "Currency exposure", changes: result.currencyChanges)
            }
        }
    }

    private var diversificationTint: Color {
        guard let before = result.effectiveHoldingsBefore, let after = result.effectiveHoldingsAfter else { return .primary }
        if after > before { return Theme.gain }
        if after < before { return .orange }
        return .primary
    }

    private var verdict: some View {
        let affordable = result.isAffordable
        return HStack(spacing: 14) {
            Image(systemName: affordable ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(affordable ? Theme.gain : Theme.loss)
            VStack(alignment: .leading, spacing: 3) {
                Text(affordable ? "You can afford this trade" : "Not enough buying power")
                    .font(.headline)
                Text("\(result.trade.side.title) \(Format.quantity(result.trade.quantity)) × \(Format.price(result.trade.price)) = \(Format.currency(result.tradeValue, code: currency))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let buyingPowerAfter = result.buyingPowerAfter {
                    Text("Buying power after: \(Format.currency(buyingPowerAfter, code: currency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((affordable ? Theme.gain : Theme.loss).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func changeCard(title: String, changes: [ExposureChange]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            Card {
                VStack(spacing: 14) {
                    ForEach(changes.prefix(8)) { change in
                        ExposureChangeRow(change: change)
                    }
                    HStack(spacing: 14) {
                        Label("Before", systemImage: "circle.fill").foregroundStyle(Color.secondary.opacity(0.5))
                        Label("After", systemImage: "circle.fill").foregroundStyle(Theme.accent)
                    }
                    .font(.caption2)
                    .labelStyle(LegendLabelStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct ExposureChangeRow: View {
    let change: ExposureChange

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(change.label).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                Text(Format.percent(change.before)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text(Format.percent(change.after)).fontWeight(.semibold)
                if change.delta != 0 {
                    Text(Format.percent(change.delta, signed: true))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(change.delta > 0 ? Theme.accent : .secondary)
                        .frame(width: 64, alignment: .trailing)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            VStack(spacing: 3) {
                WeightBar(weight: change.before.doubleValue, color: Color.secondary.opacity(0.5))
                WeightBar(weight: change.after.doubleValue, color: Theme.accent)
            }
        }
    }
}

private struct ImpactTile: View {
    let title: String
    let before: String
    let after: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(after)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("was \(before)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title.foregroundStyle(.secondary)
        }
    }
}
