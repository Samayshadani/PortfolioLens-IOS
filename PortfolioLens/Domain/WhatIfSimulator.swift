import Foundation

struct ProposedTrade: Equatable {
    let symbol: String
    let side: OrderSide
    let quantity: Decimal
    let price: Decimal
    let currency: String
}

struct ExposureChange: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let before: Decimal
    let after: Decimal
    var delta: Decimal { after - before }
}

struct WhatIfResult: Equatable {
    let trade: ProposedTrade
    let tradeValue: Decimal
    let sharesBefore: Decimal
    let sharesAfter: Decimal
    let positionWeightBefore: Decimal
    let positionWeightAfter: Decimal
    let cashBefore: Decimal
    let cashAfter: Decimal
    let buyingPowerAfter: Decimal?
    let isAffordable: Bool
    let effectiveHoldingsBefore: Decimal?
    let effectiveHoldingsAfter: Decimal?
    let sectorChanges: [ExposureChange]
    let currencyChanges: [ExposureChange]
    let warnings: [String]
}

/// Shows how a trade would reshape the portfolio *before* the order is sent.
enum WhatIfSimulator {
    static let concentrationLimit = Decimal(25) / 100
    static let sectorLimit = Decimal(40) / 100

    static func apply(_ trade: ProposedTrade, to holdings: [HoldingSnapshot]) -> [HoldingSnapshot] {
        let symbol = trade.symbol.uppercased()
        let signedQuantity = trade.side == .buy ? trade.quantity : -trade.quantity
        let cashDelta = -(signedQuantity * trade.price)
        var result = holdings

        if let index = result.firstIndex(where: { $0.source == .broker && $0.symbol == symbol }) {
            result[index].quantity += signedQuantity
            result[index].price = trade.price
            if result[index].quantity == 0 { result.remove(at: index) }
        } else {
            let info = SectorDirectory.info(for: symbol)
            result.append(HoldingSnapshot(
                id: "broker-\(symbol)", symbol: symbol, name: info.name,
                quantity: signedQuantity, price: trade.price, currency: trade.currency,
                sector: info.sector, assetClass: info.assetClass, source: .broker))
        }

        if let index = result.firstIndex(where: { $0.source == .cash && $0.currency == trade.currency }) {
            result[index].quantity += cashDelta
        } else {
            result.append(.cash(cashDelta, currency: trade.currency))
        }
        return result
    }

    static func simulate(holdings: [HoldingSnapshot], trade: ProposedTrade,
                         buyingPower: Decimal?, converter: CurrencyConverter) -> WhatIfResult {
        let symbol = trade.symbol.uppercased()
        let after = apply(trade, to: holdings)
        let tradeValue = trade.quantity * trade.price

        let sharesBefore = brokerQuantity(of: symbol, in: holdings)
        let sharesAfter = brokerQuantity(of: symbol, in: after)
        let cashBefore = cash(in: holdings, currency: trade.currency)
        let cashAfter = cash(in: after, currency: trade.currency)
        let weightBefore = weight(of: symbol, in: holdings, converter: converter)
        let weightAfter = weight(of: symbol, in: after, converter: converter)

        let isAffordable = trade.side == .sell || (buyingPower.map { tradeValue <= $0 } ?? true)
        let buyingPowerAfter = buyingPower.map { trade.side == .buy ? $0 - tradeValue : $0 + tradeValue }

        let sectorChanges = changes(before: holdings, after: after, dimension: .sector, converter: converter)
        let currencyChanges = changes(before: holdings, after: after, dimension: .currency, converter: converter)

        var warnings: [String] = []
        if !isAffordable, let buyingPower {
            warnings.append("This order needs \(Format.currency(tradeValue, code: trade.currency)) but your buying power is \(Format.currency(buyingPower, code: trade.currency)).")
        }
        if trade.side == .sell, trade.quantity > sharesBefore {
            if sharesBefore > 0 {
                warnings.append("You hold \(Format.quantity(sharesBefore)) shares, so the extra \(Format.quantity(trade.quantity - sharesBefore)) would be sold short.")
            } else {
                warnings.append("You don't own \(symbol), so this sale would open a short position.")
            }
        }
        if weightAfter > concentrationLimit, weightAfter > weightBefore {
            warnings.append("\(symbol) would become \(Format.percent(weightAfter)) of your portfolio, above the 25% guideline.")
        }
        if cashAfter < 0, cashBefore >= 0 {
            warnings.append("Your cash would go negative. That means borrowing on margin, which costs interest.")
        }
        if let sector = sectorChanges.first(where: { $0.label != "Cash" && $0.after > sectorLimit && $0.delta > 0 }) {
            warnings.append("\(sector.label) exposure would rise to \(Format.percent(sector.after)).")
        }

        return WhatIfResult(
            trade: trade,
            tradeValue: tradeValue,
            sharesBefore: sharesBefore,
            sharesAfter: sharesAfter,
            positionWeightBefore: weightBefore,
            positionWeightAfter: weightAfter,
            cashBefore: cashBefore,
            cashAfter: cashAfter,
            buyingPowerAfter: buyingPowerAfter,
            isAffordable: isAffordable,
            effectiveHoldingsBefore: ExposureAnalyzer.effectiveHoldings(holdings, converter: converter),
            effectiveHoldingsAfter: ExposureAnalyzer.effectiveHoldings(after, converter: converter),
            sectorChanges: sectorChanges,
            currencyChanges: currencyChanges,
            warnings: warnings
        )
    }

    private static func brokerQuantity(of symbol: String, in holdings: [HoldingSnapshot]) -> Decimal {
        holdings.first { $0.source == .broker && $0.symbol == symbol }?.quantity ?? 0
    }

    private static func cash(in holdings: [HoldingSnapshot], currency: String) -> Decimal {
        holdings.first { $0.source == .cash && $0.currency == currency }?.quantity ?? 0
    }

    private static func weight(of symbol: String, in holdings: [HoldingSnapshot], converter: CurrencyConverter) -> Decimal {
        let total = ExposureAnalyzer.grossTotal(holdings, converter: converter)
        guard total > 0, let holding = holdings.first(where: { $0.source == .broker && $0.symbol == symbol }) else { return 0 }
        return ExposureAnalyzer.grossValue(of: holding, converter: converter) / total
    }

    private static func changes(before: [HoldingSnapshot], after: [HoldingSnapshot],
                                dimension: ExposureDimension, converter: CurrencyConverter) -> [ExposureChange] {
        let beforeSlices = ExposureAnalyzer.slices(before, by: dimension, converter: converter, maxSlices: .max)
        let afterSlices = ExposureAnalyzer.slices(after, by: dimension, converter: converter, maxSlices: .max)
        let beforeMap = Dictionary(uniqueKeysWithValues: beforeSlices.map { ($0.label, $0.weight) })
        let afterMap = Dictionary(uniqueKeysWithValues: afterSlices.map { ($0.label, $0.weight) })
        let labels = Set(beforeMap.keys).union(afterMap.keys)
        return labels
            .map { ExposureChange(label: $0, before: beforeMap[$0] ?? 0, after: afterMap[$0] ?? 0) }
            .sorted { max($0.before, $0.after) > max($1.before, $1.after) }
    }
}
