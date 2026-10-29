import SwiftUI
import SwiftData

struct ExposureView: View {
    @Environment(MarketStore.self) private var store
    @Environment(FXStore.self) private var fx
    @Query private var manualHoldings: [ManualHolding]
    @State private var dimension: ExposureDimension = .sector

    var body: some View {
        let converter = fx.converter
        let holdings = PortfolioCalculator.holdings(account: store.account, positions: store.positions,
                                                    quotes: store.quotes, manual: manualHoldings.map(\.snapshot))
        let slices = ExposureAnalyzer.slices(holdings, by: dimension, converter: converter)
        let total = ExposureAnalyzer.grossTotal(holdings, converter: converter)
        let insights = ExposureAnalyzer.insights(holdings, converter: converter)
        let effective = ExposureAnalyzer.effectiveHoldings(holdings, converter: converter)
        let investedCount = holdings.filter { $0.assetClass != .cash }.count

        ScrollView {
            VStack(spacing: 16) {
                Picker("Group by", selection: $dimension) {
                    ForEach(ExposureDimension.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if slices.isEmpty {
                    ContentUnavailableView("Nothing to analyse yet", systemImage: "chart.pie",
                                           description: Text("Once your account loads, or you add outside holdings, your exposure appears here."))
                        .padding(.top, 40)
                } else {
                    Card {
                        VStack(spacing: 20) {
                            ZStack {
                                DonutChart(slices: slices)
                                    .frame(height: 220)
                                VStack(spacing: 2) {
                                    Text("Total exposure").font(.caption).foregroundStyle(.secondary)
                                    Text(Format.currency(total, code: converter.base))
                                        .font(.title3.bold())
                                        .monospacedDigit()
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: 130)
                            }
                            VStack(spacing: 12) {
                                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                                    SliceRow(slice: slice, color: Theme.paletteColor(index), currency: converter.base)
                                }
                            }
                        }
                    }

                    DiversificationCard(effective: effective, holdingCount: investedCount)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("What the Lens sees")
                        ForEach(insights) { InsightCard(insight: $0) }
                    }

                    Text(fxFootnote(converter))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refreshAll() }
    }

    private func fxFootnote(_ converter: CurrencyConverter) -> String {
        if converter.isApproximate {
            return "Values shown in \(converter.base) using approximate offline exchange rates. Pull to refresh when you're online."
        }
        let date = converter.asOf?.formatted(date: .abbreviated, time: .shortened) ?? "today"
        return "Values shown in \(converter.base) using ECB reference rates from Frankfurter, fetched \(date). Shorts count at their absolute size."
    }
}

private struct SliceRow: View {
    let slice: ExposureSlice
    let color: Color
    let currency: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(slice.label).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                Text(Format.currency(slice.value, code: currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Format.percent(slice.weight))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            WeightBar(weight: slice.weight.doubleValue, color: color)
        }
    }
}

private struct DiversificationCard: View {
    let effective: Decimal?
    let holdingCount: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Diversification", systemImage: "square.grid.3x3.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let effective {
                        Text(Format.quantity(effective.rounded(scale: 1)))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                }
                if let effective {
                    let score = min(effective.doubleValue / 15, 1)
                    Gauge(value: score) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinear)
                    .tint(Gradient(colors: [Theme.loss, .orange, Theme.gain]))
                    HStack {
                        Text("Concentrated").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("Diversified").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("You own \(holdingCount) assets, but by weight your portfolio behaves like \(Format.quantity(effective.rounded(scale: 1))) equal-sized ones.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add investments to measure diversification.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct InsightCard: View {
    let insight: RiskInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.severity.icon)
                .font(.title3)
                .foregroundStyle(insight.severity.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                if !insight.detail.isEmpty {
                    Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(insight.severity.color)
                .frame(width: 4)
        }
    }
}
