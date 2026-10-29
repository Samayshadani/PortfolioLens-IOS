import Foundation

enum ExposureDimension: String, CaseIterable, Identifiable {
    case sector, currency, assetClass, holding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sector: return "Sector"
        case .currency: return "Currency"
        case .assetClass: return "Asset"
        case .holding: return "Holding"
        }
    }
}

struct ExposureSlice: Identifiable, Equatable {
    var id: String { label }
    let label: String
    /// Gross value in the converter's base currency.
    let value: Decimal
    let weight: Decimal
}

struct RiskInsight: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case positive, info, caution, warning
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
}

/// Exposure uses gross values: shorts count by their absolute size (they are still risk),
/// while negative cash (margin debt) counts as zero rather than inflating the total.
enum ExposureAnalyzer {
    enum Thresholds {
        static let singleHoldingCaution = Decimal(15) / 100
        static let singleHoldingWarning = Decimal(25) / 100
        static let sectorWarning = Decimal(40) / 100
        static let currencyDominance = Decimal(90) / 100
        static let highCash = Decimal(50) / 100
        static let lowCash = Decimal(2) / 100
        static let lowEffectiveHoldings: Decimal = 5
    }

    static func grossValue(of holding: HoldingSnapshot, converter: CurrencyConverter) -> Decimal {
        guard let value = converter.convert(holding.marketValue, from: holding.currency) else { return 0 }
        if holding.assetClass == .cash { return max(value, 0) }
        return abs(value)
    }

    static func grossTotal(_ holdings: [HoldingSnapshot], converter: CurrencyConverter) -> Decimal {
        holdings.reduce(Decimal(0)) { $0 + grossValue(of: $1, converter: converter) }
    }

    static func key(for holding: HoldingSnapshot, dimension: ExposureDimension) -> String {
        switch dimension {
        case .sector: return holding.sector
        case .currency: return holding.currency.uppercased()
        case .assetClass: return holding.assetClass.title
        case .holding: return holding.source == .cash ? holding.name : holding.symbol
        }
    }

    static func slices(_ holdings: [HoldingSnapshot], by dimension: ExposureDimension,
                       converter: CurrencyConverter, maxSlices: Int = 7) -> [ExposureSlice] {
        var totals: [String: Decimal] = [:]
        for holding in holdings {
            let value = grossValue(of: holding, converter: converter)
            guard value > 0 else { continue }
            totals[key(for: holding, dimension: dimension), default: 0] += value
        }
        let total = totals.values.reduce(Decimal(0), +)
        guard total > 0 else { return [] }

        var sorted = totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        if maxSlices > 1, sorted.count > maxSlices {
            let tail = sorted[(maxSlices - 1)...].reduce(Decimal(0)) { $0 + $1.value }
            sorted = Array(sorted.prefix(maxSlices - 1)) + [(key: "Other", value: tail)]
        }
        return sorted.map { ExposureSlice(label: $0.key, value: $0.value, weight: $0.value / total) }
    }

    /// 1 / Herfindahl index of non-cash holdings: "your portfolio behaves like N equal-weight positions".
    static func effectiveHoldings(_ holdings: [HoldingSnapshot], converter: CurrencyConverter) -> Decimal? {
        let values = holdings
            .filter { $0.assetClass != .cash }
            .map { grossValue(of: $0, converter: converter) }
            .filter { $0 > 0 }
        let total = values.reduce(Decimal(0), +)
        guard total > 0 else { return nil }
        let hhi = values.reduce(Decimal(0)) { partial, value in
            let weight = value / total
            return partial + weight * weight
        }
        return hhi > 0 ? 1 / hhi : nil
    }

    static func insights(_ holdings: [HoldingSnapshot], converter: CurrencyConverter) -> [RiskInsight] {
        let total = grossTotal(holdings, converter: converter)
        guard total > 0 else { return [] }
        var result: [RiskInsight] = []
        let invested = holdings.filter { $0.assetClass != .cash }

        if let top = invested.max(by: { grossValue(of: $0, converter: converter) < grossValue(of: $1, converter: converter) }) {
            let weight = grossValue(of: top, converter: converter) / total
            if weight >= Thresholds.singleHoldingWarning {
                result.append(RiskInsight(
                    id: "holding", severity: .warning,
                    title: "\(top.symbol) is \(Format.percent(weight)) of everything you own",
                    detail: "A single bad earnings report could move your whole net worth. Many investors cap one position at 10–20%."))
            } else if weight >= Thresholds.singleHoldingCaution {
                result.append(RiskInsight(
                    id: "holding", severity: .caution,
                    title: "\(top.symbol) is your largest bet at \(Format.percent(weight))",
                    detail: "Not extreme, but keep an eye on it as the price moves."))
            }
        }

        let sectors = slices(holdings, by: .sector, converter: converter, maxSlices: .max)
        if let topSector = sectors.first(where: { !["Cash", "Broad Market", SectorDirectory.unclassified].contains($0.label) }),
           topSector.weight >= Thresholds.sectorWarning {
            result.append(RiskInsight(
                id: "sector", severity: .warning,
                title: "\(Format.percent(topSector.weight)) is in \(topSector.label)",
                detail: "Stocks in one sector tend to fall together. A broad index fund or another sector would spread the risk."))
        }

        let currencies = slices(holdings, by: .currency, converter: converter, maxSlices: .max)
        if let top = currencies.first, top.weight >= Thresholds.currencyDominance {
            let share = currencies.count == 1 ? "All" : Format.percent(top.weight)
            result.append(RiskInsight(
                id: "currency", severity: .info,
                title: "\(share) of your wealth is in \(top.label)",
                detail: "If you'll spend this money in another currency, exchange-rate moves are a hidden risk. Add outside holdings to see the full picture."))
        }

        let cashValue = holdings.filter { $0.assetClass == .cash }.reduce(Decimal(0)) { $0 + grossValue(of: $1, converter: converter) }
        let cashWeight = cashValue / total
        if cashWeight >= Thresholds.highCash {
            result.append(RiskInsight(
                id: "cash", severity: .info,
                title: "\(Format.percent(cashWeight)) is sitting in cash",
                detail: "Cash is safe but loses value to inflation over time."))
        } else if cashWeight < Thresholds.lowCash, !invested.isEmpty {
            result.append(RiskInsight(
                id: "cash", severity: .caution,
                title: "Almost no cash buffer",
                detail: "With under 2% in cash you may have to sell at a bad time to raise money."))
        }

        if invested.count >= 3, let effective = effectiveHoldings(holdings, converter: converter),
           effective < Thresholds.lowEffectiveHoldings {
            result.append(RiskInsight(
                id: "diversification", severity: .caution,
                title: "Behaves like \(Format.quantity(effective.rounded(scale: 1))) equal-sized holdings",
                detail: "You own \(invested.count) assets, but the weights are uneven, so a few of them drive most of your results."))
        }

        if result.isEmpty {
            result.append(RiskInsight(
                id: "ok", severity: .positive,
                title: "No major concentration risks",
                detail: "No single holding, sector or currency dominates your portfolio."))
        }
        return result.sorted { $0.severity > $1.severity }
    }
}
