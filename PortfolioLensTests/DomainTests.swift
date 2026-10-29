import XCTest
@testable import PortfolioLens

private func dec(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func stock(_ symbol: String, quantity: Decimal, price: Decimal, sector: String = "Technology",
                   currency: String = "USD") -> HoldingSnapshot {
    HoldingSnapshot(id: "broker-\(symbol)", symbol: symbol, name: symbol, quantity: quantity, price: price,
                    currency: currency, sector: sector, assetClass: .equity, source: .broker)
}

private let usd = CurrencyConverter(base: "USD", rates: ["INR": 83, "EUR": dec("0.9")])

final class CurrencyConverterTests: XCTestCase {
    func testConvertsIntoBaseByDividingByRate() {
        let inrBase = CurrencyConverter(base: "INR", rates: ["USD": dec("0.012")])
        XCTAssertEqual(inrBase.convert(12, from: "USD"), 1000)
    }

    func testBaseCurrencyIsIdentityAndCaseInsensitive() {
        XCTAssertEqual(usd.convert(42, from: "usd"), 42)
    }

    func testUnknownCurrencyReturnsNil() {
        XCTAssertNil(usd.convert(10, from: "XYZ"))
    }

    func testFallbackRatesCrossConvert() {
        let inr = FallbackRates.converter(base: "INR")
        XCTAssertTrue(inr.isApproximate)
        let converted = inr.convert(1, from: "USD")!
        XCTAssertEqual(converted.rounded(scale: 1), dec("88.5"))
    }
}

final class PortfolioCalculatorTests: XCTestCase {
    private let account = Account(id: "a", accountNumber: "PA1", currency: "USD", status: "ACTIVE",
                                  cash: 1000, equity: 2100, lastEquity: 2050, buyingPower: 2000,
                                  longMarketValue: 1100, maintenanceMargin: 0)
    private let position = Position(symbol: "AAPL", quantity: 10, averageEntryPrice: 100,
                                    currentPrice: 110, lastDayPrice: 105, assetClass: "us_equity")

    func testSummaryUsesLiveQuoteOverStaleRestPrice() {
        let quotes = ["AAPL": Quote(symbol: "AAPL", price: 120, previousClose: 105, updatedAt: .now)]
        let summary = PortfolioCalculator.summary(account: account, positions: [position], quotes: quotes,
                                                  manual: [], converter: usd)
        XCTAssertEqual(summary.investedValue, 1200)
        XCTAssertEqual(summary.totalValue, 2200)
        XCTAssertEqual(summary.dayChange, 150)
        XCTAssertEqual(summary.unrealizedPL, 200)
        XCTAssertEqual(summary.unrealizedPLPercent, dec("0.2"))
        XCTAssertEqual(summary.dayChangePercent, Decimal(150) / Decimal(2050))
    }

    func testManualHoldingsAreConvertedIntoBase() {
        let fund = HoldingSnapshot(id: "m1", symbol: "FUND", name: "Index fund", quantity: 100, price: 83,
                                   currency: "INR", sector: "Broad Market", assetClass: .etf, source: .manual)
        let summary = PortfolioCalculator.summary(account: account, positions: [position], quotes: [:],
                                                  manual: [fund], converter: usd)
        XCTAssertEqual(summary.manualValue, 100)
        XCTAssertEqual(summary.totalValue, 1000 + 1100 + 100)
    }

    func testUnconvertibleCurrenciesAreReportedNotSilentlyCounted() {
        let odd = HoldingSnapshot(id: "m2", symbol: "X", name: "X", quantity: 1, price: 500,
                                  currency: "XYZ", sector: "Other", assetClass: .other, source: .manual)
        let summary = PortfolioCalculator.summary(account: account, positions: [], quotes: [:],
                                                  manual: [odd], converter: usd)
        XCTAssertEqual(summary.unconvertedCurrencies, ["XYZ"])
        XCTAssertEqual(summary.manualValue, 0)
    }

    func testHoldingsIncludeCashAndClassifySectors() {
        let holdings = PortfolioCalculator.holdings(account: account, positions: [position], quotes: [:], manual: [])
        XCTAssertEqual(holdings.count, 2)
        XCTAssertEqual(holdings.first?.sector, "Technology")
        XCTAssertEqual(holdings.last?.assetClass, .cash)
        XCTAssertEqual(holdings.last?.marketValue, 1000)
    }
}

final class ExposureAnalyzerTests: XCTestCase {
    private let holdings = [
        stock("A", quantity: 6, price: 100),
        stock("B", quantity: 2, price: 100),
        stock("C", quantity: 2, price: 100, sector: "Energy")
    ]

    func testSectorWeights() {
        let slices = ExposureAnalyzer.slices(holdings, by: .sector, converter: usd)
        XCTAssertEqual(slices.map(\.label), ["Technology", "Energy"])
        XCTAssertEqual(slices.first?.weight, dec("0.8"))
    }

    func testTailIsGroupedIntoOther() {
        let slices = ExposureAnalyzer.slices(holdings, by: .holding, converter: usd, maxSlices: 2)
        XCTAssertEqual(slices.map(\.label), ["A", "Other"])
        XCTAssertEqual(slices.last?.value, 400)
    }

    func testShortsCountAtAbsoluteSizeAndMarginDebtIsIgnored() {
        let short = stock("S", quantity: -5, price: 100)
        let debt = HoldingSnapshot.cash(-300, currency: "USD")
        XCTAssertEqual(ExposureAnalyzer.grossValue(of: short, converter: usd), 500)
        XCTAssertEqual(ExposureAnalyzer.grossValue(of: debt, converter: usd), 0)
    }

    func testEffectiveHoldingsOfEqualWeightsEqualsCount() {
        let equal = [stock("A", quantity: 1, price: 100), stock("B", quantity: 1, price: 100),
                     stock("C", quantity: 1, price: 100), stock("D", quantity: 1, price: 100)]
        XCTAssertEqual(ExposureAnalyzer.effectiveHoldings(equal, converter: usd), 4)
    }

    func testConcentrationProducesWarningFirst() {
        let insights = ExposureAnalyzer.insights(holdings, converter: usd)
        XCTAssertEqual(insights.first?.severity, .warning)
        XCTAssertTrue(insights.contains { $0.id == "holding" })
        XCTAssertTrue(insights.contains { $0.id == "sector" })
    }

    func testBalancedPortfolioGetsPositiveInsight() {
        let sectors = ["Technology", "Energy", "Financials", "Health Care", "Utilities",
                       "Industrials", "Materials", "Consumer Staples", "Real Estate", "Communication Services"]
        var balanced = sectors.enumerated().map { stock("S\($0.offset)", quantity: 1, price: 100, sector: $0.element) }
        balanced.append(stock("EU1", quantity: 1, price: 100, sector: "International", currency: "EUR"))
        balanced.append(stock("EU2", quantity: 1, price: 100, sector: "International", currency: "EUR"))
        balanced.append(.cash(100, currency: "USD"))
        let insights = ExposureAnalyzer.insights(balanced, converter: usd)
        XCTAssertEqual(insights.map(\.id), ["ok"])
    }
}

final class WhatIfSimulatorTests: XCTestCase {
    private let holdings = [stock("AAPL", quantity: 10, price: 100), HoldingSnapshot.cash(1000, currency: "USD")]

    private func trade(_ side: OrderSide, _ quantity: Decimal, _ symbol: String = "AAPL") -> ProposedTrade {
        ProposedTrade(symbol: symbol, side: side, quantity: quantity, price: 100, currency: "USD")
    }

    func testBuyIncreasesWeightAndSpendsCash() {
        let result = WhatIfSimulator.simulate(holdings: holdings, trade: trade(.buy, 5), buyingPower: 1000, converter: usd)
        XCTAssertEqual(result.sharesAfter, 15)
        XCTAssertEqual(result.cashAfter, 500)
        XCTAssertEqual(result.positionWeightBefore, dec("0.5"))
        XCTAssertEqual(result.positionWeightAfter, dec("0.75"))
        XCTAssertEqual(result.buyingPowerAfter, 500)
        XCTAssertTrue(result.isAffordable)
        XCTAssertTrue(result.warnings.contains { $0.contains("25%") })
    }

    func testBuyBeyondBuyingPowerIsNotAffordable() {
        let result = WhatIfSimulator.simulate(holdings: holdings, trade: trade(.buy, 20), buyingPower: 1000, converter: usd)
        XCTAssertFalse(result.isAffordable)
        XCTAssertTrue(result.warnings.contains { $0.contains("buying power") })
        XCTAssertTrue(result.warnings.contains { $0.contains("margin") })
    }

    func testSellingEverythingRemovesPosition() {
        let result = WhatIfSimulator.simulate(holdings: holdings, trade: trade(.sell, 10), buyingPower: 1000, converter: usd)
        XCTAssertEqual(result.sharesAfter, 0)
        XCTAssertEqual(result.cashAfter, 2000)
        XCTAssertEqual(result.positionWeightAfter, 0)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testOverSellingWarnsAboutShort() {
        let result = WhatIfSimulator.simulate(holdings: holdings, trade: trade(.sell, 15), buyingPower: nil, converter: usd)
        XCTAssertEqual(result.sharesAfter, -5)
        XCTAssertTrue(result.warnings.contains { $0.contains("short") })
    }

    func testBuyingNewSymbolUsesDirectorySector() {
        let result = WhatIfSimulator.simulate(holdings: holdings, trade: trade(.buy, 2, "XOM"), buyingPower: nil, converter: usd)
        XCTAssertTrue(result.sectorChanges.contains { $0.label == "Energy" && $0.before == 0 && $0.after > 0 })
    }
}

final class AlertDirectionTests: XCTestCase {
    func testTriggers() {
        XCTAssertTrue(AlertDirection.above.isTriggered(by: 101, target: 100))
        XCTAssertTrue(AlertDirection.above.isTriggered(by: 100, target: 100))
        XCTAssertFalse(AlertDirection.above.isTriggered(by: 99, target: 100))
        XCTAssertTrue(AlertDirection.below.isTriggered(by: 99, target: 100))
        XCTAssertFalse(AlertDirection.below.isTriggered(by: 101, target: 100))
    }
}

final class DecimalParsingTests: XCTestCase {
    func testApiStrings() {
        XCTAssertEqual(Decimal(apiString: "1234.5678"), dec("1234.5678"))
        XCTAssertNil(Decimal(apiString: nil))
        XCTAssertNil(Decimal(apiString: ""))
    }

    func testUserInputAcceptsPlainDecimals() {
        XCTAssertEqual(Decimal.parseUserInput(" 12.5 "), dec("12.5"))
        XCTAssertEqual(Decimal.parseUserInput(".5"), dec("0.5"))
        XCTAssertNil(Decimal.parseUserInput(""))
        XCTAssertNil(Decimal.parseUserInput("12abc"))
        XCTAssertNil(Decimal.parseUserInput("1.2.3"))
    }

    func testWholeNumberDetection() {
        XCTAssertTrue(Decimal(10).isWholeNumber)
        XCTAssertFalse(dec("10.5").isWholeNumber)
    }
}
