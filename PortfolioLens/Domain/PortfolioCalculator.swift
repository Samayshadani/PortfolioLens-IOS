import Foundation

/// A broker-agnostic view of anything the user owns, used by every analysis in the app.
struct HoldingSnapshot: Identifiable, Equatable {
    enum Source: String { case broker, manual, cash }

    let id: String
    let symbol: String
    let name: String
    var quantity: Decimal
    var price: Decimal
    let currency: String
    let sector: String
    let assetClass: AssetClass
    let source: Source

    var marketValue: Decimal { quantity * price }

    static func cash(_ amount: Decimal, currency: String) -> HoldingSnapshot {
        HoldingSnapshot(
            id: "cash-\(currency)", symbol: "CASH", name: "Cash (\(currency))",
            quantity: amount, price: 1, currency: currency,
            sector: "Cash", assetClass: .cash, source: .cash
        )
    }
}

/// All amounts are in `baseCurrency`.
struct PortfolioSummary: Equatable {
    let baseCurrency: String
    let totalValue: Decimal
    let brokerEquity: Decimal
    let cash: Decimal
    let investedValue: Decimal
    let buyingPower: Decimal?
    let dayChange: Decimal
    let dayChangePercent: Decimal?
    let unrealizedPL: Decimal
    let unrealizedPLPercent: Decimal?
    let manualValue: Decimal
    let unconvertedCurrencies: [String]
}

enum PortfolioCalculator {
    static func livePrice(for position: Position, quotes: [String: Quote]) -> Decimal {
        quotes[position.symbol]?.price ?? position.currentPrice
    }

    static func previousClose(for position: Position, quotes: [String: Quote]) -> Decimal {
        quotes[position.symbol]?.previousClose ?? position.lastDayPrice
    }

    static func holdings(account: Account?, positions: [Position], quotes: [String: Quote],
                         manual: [HoldingSnapshot]) -> [HoldingSnapshot] {
        let currency = account?.currency ?? "USD"
        var result = positions.map { position -> HoldingSnapshot in
            let info = SectorDirectory.info(for: position.symbol)
            return HoldingSnapshot(
                id: "broker-\(position.symbol)",
                symbol: position.symbol,
                name: info.name,
                quantity: position.quantity,
                price: livePrice(for: position, quotes: quotes),
                currency: currency,
                sector: position.isCrypto ? "Crypto" : info.sector,
                assetClass: position.isCrypto ? .crypto : info.assetClass,
                source: .broker
            )
        }
        if let account, account.cash != 0 {
            result.append(.cash(account.cash, currency: currency))
        }
        result.append(contentsOf: manual)
        return result
    }

    static func summary(account: Account?, positions: [Position], quotes: [String: Quote],
                        manual: [HoldingSnapshot], converter: CurrencyConverter) -> PortfolioSummary {
        let brokerCurrency = account?.currency ?? "USD"
        var invested: Decimal = 0
        var dayChange: Decimal = 0
        var unrealized: Decimal = 0
        var costBasis: Decimal = 0

        for position in positions {
            let price = livePrice(for: position, quotes: quotes)
            invested += position.quantity * price
            dayChange += position.quantity * (price - previousClose(for: position, quotes: quotes))
            unrealized += position.quantity * (price - position.averageEntryPrice)
            costBasis += abs(position.quantity * position.averageEntryPrice)
        }

        let cash = account?.cash ?? 0
        var unconverted: Set<String> = []
        func toBase(_ amount: Decimal, _ currency: String) -> Decimal {
            if let value = converter.convert(amount, from: currency) { return value }
            unconverted.insert(currency.uppercased())
            return 0
        }

        let manualValue = manual.reduce(Decimal(0)) { $0 + toBase($1.marketValue, $1.currency) }
        let brokerEquity = toBase(cash + invested, brokerCurrency)
        let dayChangeBase = toBase(dayChange, brokerCurrency)
        let previousEquity = brokerEquity - dayChangeBase
        let cashBase = toBase(cash, brokerCurrency)
        let investedBase = toBase(invested, brokerCurrency)
        let buyingPower = account.map { toBase($0.buyingPower, brokerCurrency) }
        let unrealizedBase = toBase(unrealized, brokerCurrency)

        return PortfolioSummary(
            baseCurrency: converter.base,
            totalValue: brokerEquity + manualValue,
            brokerEquity: brokerEquity,
            cash: cashBase,
            investedValue: investedBase,
            buyingPower: buyingPower,
            dayChange: dayChangeBase,
            dayChangePercent: previousEquity == 0 ? nil : dayChangeBase / previousEquity,
            unrealizedPL: unrealizedBase,
            unrealizedPLPercent: costBasis == 0 ? nil : unrealized / costBasis,
            manualValue: manualValue,
            unconvertedCurrencies: unconverted.sorted()
        )
    }
}
