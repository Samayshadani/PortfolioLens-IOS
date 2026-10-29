import SwiftUI
import SwiftData
import Charts

struct SymbolDetailView: View {
    let symbol: String

    private enum ActiveSheet: Identifiable {
        case order(OrderSide)
        case whatIf
        case alert

        var id: String {
            switch self {
            case .order(let side): return "order-\(side.rawValue)"
            case .whatIf: return "whatIf"
            case .alert: return "alert"
            }
        }
    }

    @Environment(MarketStore.self) private var store
    @Environment(AlertCenter.self) private var alertCenter
    @Query private var alerts: [PriceAlert]
    @State private var range: ChartRange = .month
    @State private var bars: [PriceBar] = []
    @State private var isLoadingBars = false
    @State private var chartError: String?
    @State private var selectedIndex: Int?
    @State private var activeSheet: ActiveSheet?

    init(symbol: String) {
        self.symbol = symbol
        _alerts = Query(filter: #Predicate<PriceAlert> { $0.symbol == symbol },
                        sort: \PriceAlert.createdAt, order: .reverse)
    }

    private var quote: Quote? { store.quotes[symbol] }
    private var info: SecurityInfo { SectorDirectory.info(for: symbol) }
    private var position: Position? { store.position(for: symbol) }
    private var currency: String { store.account?.currency ?? "USD" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                chartCard
                actionButtons
                if let position { positionCard(position) }
                alertsCard
                ordersCard
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .task { _ = await store.quote(for: symbol) }
        .task(id: range) { await loadBars() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .order(let side):
                OrderTicketView(symbol: symbol, side: side)
            case .whatIf:
                NavigationStack {
                    WhatIfView(initialSymbol: symbol, quantity: 1)
                        .navigationTitle("What-if")
                        .navigationBarTitleDisplayMode(.inline)
                }
            case .alert:
                PriceAlertEditor(symbol: symbol, currentPrice: quote?.price)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        let selectedBar = selectedIndex.flatMap { bars.indices.contains($0) ? bars[$0] : nil }
        let displayPrice = selectedBar?.close ?? quote?.price
        let rangeChange: Decimal? = {
            guard let first = bars.first?.close, first != 0, let last = displayPrice else { return nil }
            return (last - first) / first
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(info.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(info.sector)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.fieldBackground, in: Capsule())
            }
            if let displayPrice {
                LivePriceText(value: displayPrice, font: .system(size: 40, weight: .bold, design: .rounded))
            } else {
                ProgressView().frame(height: 48)
            }
            HStack(spacing: 8) {
                if let selectedBar {
                    Text(selectedBar.time.formatted(date: .abbreviated, time: range == .day || range == .week ? .shortened : .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ChangePill(percent: quote?.changePercent)
                    Text("today").font(.subheadline).foregroundStyle(.secondary)
                }
                if let rangeChange {
                    ChangePill(percent: rangeChange, style: .subtle)
                    Text(range.rawValue).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chartCard: some View {
        Card {
            VStack(spacing: 14) {
                Group {
                    if isLoadingBars && bars.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let chartError, bars.isEmpty {
                        ContentUnavailableView("Chart unavailable", systemImage: "chart.xyaxis.line",
                                               description: Text(chartError))
                    } else if bars.isEmpty {
                        ContentUnavailableView("No trades in this range", systemImage: "moon.zzz",
                                               description: Text("The market may be closed."))
                    } else {
                        PriceChart(bars: bars, selectedIndex: $selectedIndex)
                    }
                }
                .frame(height: 230)

                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { activeSheet = .order(.buy) } label: {
                Text("Buy").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.gain)

            Button { activeSheet = .order(.sell) } label: {
                Text("Sell").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.loss)

            Button { activeSheet = .whatIf } label: {
                Label("What-if", systemImage: "scope").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { activeSheet = .alert } label: {
                Image(systemName: "bell.badge")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add price alert")
        }
        .controlSize(.large)
        .font(.subheadline.weight(.semibold))
    }

    private func positionCard(_ position: Position) -> some View {
        let price = quote?.price ?? position.currentPrice
        let value = position.quantity * price
        let costBasis = position.quantity * position.averageEntryPrice
        let profit = value - costBasis
        let profitPercent: Decimal? = costBasis == 0 ? nil : profit / abs(costBasis)
        let previous = quote?.previousClose ?? position.lastDayPrice
        let dayProfit = position.quantity * (price - previous)

        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Your position")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                MetricTile(title: "Shares", value: Format.quantity(position.quantity),
                           detail: "Avg \(Format.price(position.averageEntryPrice))")
                MetricTile(title: "Market value", value: Format.currency(value, code: currency))
                MetricTile(title: "Total return", value: Format.signedCurrency(profit, code: currency),
                           detail: profitPercent.map { Format.percent($0, signed: true) },
                           tint: Theme.color(for: profit))
                MetricTile(title: "Today", value: Format.signedCurrency(dayProfit, code: currency),
                           tint: Theme.color(for: dayProfit))
            }
        }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Price alerts")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if alerts.isEmpty {
                        Button { activeSheet = .alert } label: {
                            Label("Notify me when \(symbol) hits a price", systemImage: "bell")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contextMenu {
                                if !alert.isActive {
                                    Button("Re-arm", systemImage: "arrow.clockwise") {
                                        alertCenter.reactivate(alert, currentPrice: quote?.price)
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    alertCenter.delete(alert)
                                }
                            }
                        if alert.id != alerts.last?.id { Divider().padding(.leading, 16) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ordersCard: some View {
        let recent = Array(store.orders.filter { $0.symbol == symbol }.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Recent orders")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(recent) { order in
                            OrderRow(order: order)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            if order.id != recent.last?.id { Divider().padding(.leading, 16) }
                        }
                    }
                }
            }
        }
    }

    private func loadBars() async {
        isLoadingBars = true
        chartError = nil
        selectedIndex = nil
        defer { isLoadingBars = false }
        do {
            let result = try await store.bars(for: symbol, range: range)
            withAnimation(.easeInOut(duration: 0.3)) { bars = result }
        } catch is CancellationError {
            return
        } catch {
            bars = []
            chartError = error.localizedDescription
        }
    }
}

struct PriceChart: View {
    let bars: [PriceBar]
    @Binding var selectedIndex: Int?

    var body: some View {
        let closes = bars.map(\.close.doubleValue)
        let lower = closes.min() ?? 0
        let upper = closes.max() ?? 1
        let padding = max((upper - lower) * 0.1, upper * 0.002)
        let baseline = lower - padding
        let isUp = (closes.last ?? 0) >= (closes.first ?? 0)
        let tint = isUp ? Theme.gain : Theme.loss

        Chart {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                AreaMark(
                    x: .value("Index", index),
                    yStart: .value("Baseline", baseline),
                    yEnd: .value("Price", bar.close.doubleValue)
                )
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))

                LineMark(x: .value("Index", index), y: .value("Price", bar.close.doubleValue))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let selectedIndex, bars.indices.contains(selectedIndex) {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Selected", selectedIndex),
                          y: .value("Price", bars[selectedIndex].close.doubleValue))
                    .foregroundStyle(tint)
                    .symbolSize(70)
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(bars.count - 1, 1))
        .chartYScale(domain: baseline...(upper + padding))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }
}

struct AlertRow: View {
    let alert: PriceAlert

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.direction.icon)
                .font(.title3)
                .foregroundStyle(alert.isActive ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(alert.symbol) \(alert.direction.shortVerb) \(Format.price(alert.targetPrice))")
                    .font(.subheadline.weight(.semibold))
                if let triggeredAt = alert.triggeredAt {
                    Text("Triggered \(triggeredAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Created \(alert.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(alert.isActive ? "Active" : "Done")
                .font(.caption.weight(.semibold))
                .foregroundStyle(alert.isActive ? Theme.accent : .secondary)
        }
    }
}

struct PriceAlertEditor: View {
    let symbol: String
    let currentPrice: Decimal?
    @Environment(AlertCenter.self) private var alertCenter
    @Environment(\.dismiss) private var dismiss
    @State private var targetText = ""

    private var target: Decimal? { Decimal.parseUserInput(targetText) }

    private var direction: AlertDirection {
        guard let target, let currentPrice else { return .above }
        return target >= currentPrice ? .above : .below
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let currentPrice {
                        LabeledContent("Current price", value: Format.price(currentPrice))
                    }
                    LabeledContent("Target price") {
                        TextField("0.00", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if let target, target > 0 {
                        Text("You'll get a notification when \(symbol) \(direction.verb) \(Format.price(target)).")
                    }
                }

                if let currentPrice {
                    Section("Quick targets") {
                        HStack {
                            ForEach([-10, -5, 5, 10], id: \.self) { percent in
                                Button("\(percent > 0 ? "+" : "")\(percent)%") {
                                    let value = (currentPrice * (1 + Decimal(percent) / 100)).rounded(scale: 2)
                                    targetText = Format.plainNumber(value)
                                }
                                .buttonStyle(.bordered)
                                .tint(percent > 0 ? Theme.gain : Theme.loss)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Alert for \(symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let target {
                            alertCenter.addAlert(symbol: symbol, target: target, currentPrice: currentPrice)
                        }
                        dismiss()
                    }
                    .disabled((target ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
