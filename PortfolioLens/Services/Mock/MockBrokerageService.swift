import Foundation

/// A self-contained simulated market: random-walk prices, a starter portfolio and
/// orders that fill against the simulated price. Used for demo mode and SwiftUI previews.
actor MockBrokerageService: BrokerageService {
    nonisolated let displayName = "Demo market"
    nonisolated let isSimulated = true

    private struct Holding {
        var quantity: Decimal
        var averagePrice: Decimal
    }

    private var prices: [String: Decimal] = [:]
    private var previousCloses: [String: Decimal] = [:]
    private var holdings: [String: Holding] = [:]
    private var orders: [Order] = []
    private var cash: Decimal

    init() {
        let starter: [(String, String, String, String)] = [
            ("AAPL", "228.40", "25", "182.10"),
            ("MSFT", "415.20", "12", "352.75"),
            ("NVDA", "132.65", "60", "88.40"),
            ("JPM", "238.10", "18", "196.30"),
            ("XOM", "112.80", "30", "118.25"),
            ("VOO", "532.40", "8", "471.90")
        ]
        let watchOnly: [(String, String)] = [
            ("AMZN", "186.50"), ("GOOGL", "172.30"), ("TSLA", "251.70"), ("SPY", "578.20"),
            ("META", "590.10"), ("NFLX", "712.40"), ("IBKR", "158.90"), ("INFY", "22.15")
        ]

        var prices: [String: Decimal] = [:]
        var holdings: [String: Holding] = [:]
        for (symbol, price, quantity, average) in starter {
            prices[symbol] = Self.decimal(price)
            holdings[symbol] = Holding(quantity: Self.decimal(quantity), averagePrice: Self.decimal(average))
        }
        for (symbol, price) in watchOnly { prices[symbol] = Self.decimal(price) }

        var previousCloses: [String: Decimal] = [:]
        for (symbol, price) in prices { previousCloses[symbol] = Self.previousClose(for: symbol, price: price) }

        self.prices = prices
        self.previousCloses = previousCloses
        self.holdings = holdings
        self.cash = Self.decimal("18500")
    }

    // MARK: BrokerageService

    func fetchAccount() async throws -> Account {
        try await simulateLatency()
        var invested: Decimal = 0
        var previousInvested: Decimal = 0
        for (symbol, holding) in holdings {
            invested += holding.quantity * price(for: symbol)
            previousInvested += holding.quantity * (previousCloses[symbol] ?? price(for: symbol))
        }
        return Account(
            id: "demo", accountNumber: "DEMO-0001", currency: "USD", status: "ACTIVE",
            cash: cash, equity: cash + invested, lastEquity: cash + previousInvested,
            buyingPower: max(cash, 0), longMarketValue: invested,
            maintenanceMargin: (invested / 4).rounded(scale: 2)
        )
    }

    func fetchPositions() async throws -> [Position] {
        try await simulateLatency()
        return holdings.map { symbol, holding in
            let current = price(for: symbol)
            return Position(
                symbol: symbol, quantity: holding.quantity, averageEntryPrice: holding.averagePrice,
                currentPrice: current, lastDayPrice: previousCloses[symbol] ?? current, assetClass: "us_equity"
            )
        }
    }

    func fetchOrders() async throws -> [Order] {
        try await simulateLatency()
        return orders
    }

    func placeOrder(_ request: OrderRequest) async throws -> Order {
        try await simulateLatency()
        let symbol = request.symbol.uppercased()
        guard request.quantity > 0 else {
            throw APIError.server(status: 422, message: "Quantity must be greater than zero.")
        }
        if request.type == .limit, (request.limitPrice ?? 0) <= 0 {
            throw APIError.server(status: 422, message: "Limit orders need a limit price.")
        }

        let market = price(for: symbol)
        let checkPrice = request.type == .limit ? (request.limitPrice ?? market) : market
        try validate(symbol: symbol, side: request.side, quantity: request.quantity, price: checkPrice)

        var order = Order(
            id: UUID().uuidString, symbol: symbol, quantity: request.quantity, filledQuantity: 0,
            filledAveragePrice: nil, side: request.side, typeName: request.type.rawValue,
            timeInForceName: request.timeInForce.rawValue, limitPrice: request.limitPrice,
            status: "new", createdAt: .now
        )
        if request.type == .market || isMarketable(order, market: market) {
            order = fill(order, at: market)
        }
        orders.insert(order, at: 0)
        return order
    }

    func cancelOrder(id: String) async throws {
        try await simulateLatency()
        guard let index = orders.firstIndex(where: { $0.id == id }), orders[index].isOpen else {
            throw APIError.server(status: 422, message: "This order can no longer be cancelled.")
        }
        orders[index].status = "canceled"
    }

    func fetchSnapshots(symbols: [String]) async throws -> [String: Quote] {
        try await simulateLatency()
        var quotes: [String: Quote] = [:]
        for symbol in symbols {
            let current = price(for: symbol)
            quotes[symbol] = Quote(symbol: symbol, price: current, previousClose: previousCloses[symbol], updatedAt: .now)
        }
        return quotes
    }

    func fetchBars(symbol: String, range: ChartRange) async throws -> [PriceBar] {
        try await simulateLatency()
        let shape = range.mockShape
        var value = price(for: symbol).doubleValue
        var closes = [value]
        for _ in 1..<shape.count {
            value /= 1 + Self.gaussian() * shape.volatility + shape.volatility / 8
            closes.append(max(value, 0.01))
        }
        closes.reverse()

        let end = Date()
        return closes.enumerated().map { index, close in
            let time = end.addingTimeInterval(-Double(shape.count - 1 - index) * shape.step)
            let price = Decimal(close).rounded(scale: 2)
            return PriceBar(time: time, open: price, high: price, low: price, close: price,
                            volume: Int.random(in: 1_000...90_000))
        }
    }

    func asset(symbol: String) async throws -> AssetInfo {
        try await simulateLatency()
        let normalized = symbol.uppercased()
        guard normalized.range(of: #"^[A-Z]{1,5}(\.[A-Z])?$"#, options: .regularExpression) != nil else {
            throw APIError.notFound("\(normalized) isn't a valid US ticker.")
        }
        _ = price(for: normalized)
        return AssetInfo(symbol: normalized, name: SectorDirectory.info(for: normalized).name,
                         exchange: "DEMO", tradable: true, fractionable: true)
    }

    nonisolated func priceStream(symbols: [String]) -> AsyncThrowingStream<PriceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.connected)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(900))
                    if Task.isCancelled { break }
                    for tick in await self.advance(symbols: symbols) {
                        continuation.yield(.tick(tick))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Simulation

    private func advance(symbols: [String]) -> [PriceTick] {
        let now = Date()
        var ticks: [PriceTick] = []
        for symbol in symbols where Double.random(in: 0..<1) < 0.55 {
            let current = price(for: symbol)
            let shock = Self.gaussian() * 0.0012 + 0.00002
            let next = max(Self.decimal("0.01"), (current * Decimal(1 + shock)).rounded(scale: 2))
            prices[symbol] = next
            ticks.append(PriceTick(symbol: symbol, price: next, timestamp: now))
        }
        processOpenOrders()
        return ticks
    }

    private func processOpenOrders() {
        for index in orders.indices where orders[index].isOpen {
            let order = orders[index]
            let market = price(for: order.symbol)
            guard isMarketable(order, market: market) else { continue }
            do {
                try validate(symbol: order.symbol, side: order.side, quantity: order.quantity, price: market)
                orders[index] = fill(order, at: market)
            } catch {
                orders[index].status = "rejected"
            }
        }
    }

    private func isMarketable(_ order: Order, market: Decimal) -> Bool {
        guard let limit = order.limitPrice else { return true }
        return order.side == .buy ? market <= limit : market >= limit
    }

    private func validate(symbol: String, side: OrderSide, quantity: Decimal, price: Decimal) throws {
        switch side {
        case .buy:
            let cost = quantity * price
            if cost > cash {
                throw APIError.server(status: 403, message: "Insufficient buying power: this order needs \(Format.currency(cost, code: "USD")) and you have \(Format.currency(cash, code: "USD")).")
            }
        case .sell:
            let held = holdings[symbol]?.quantity ?? 0
            if quantity > held {
                throw APIError.server(status: 403, message: "Insufficient quantity: you hold \(Format.quantity(held)) \(symbol). Demo mode doesn't support short selling.")
            }
        }
    }

    private func fill(_ order: Order, at price: Decimal) -> Order {
        var filled = order
        let value = order.quantity * price
        switch order.side {
        case .buy:
            let existing = holdings[order.symbol] ?? Holding(quantity: 0, averagePrice: 0)
            let quantity = existing.quantity + order.quantity
            let average = ((existing.quantity * existing.averagePrice + value) / quantity).rounded(scale: 4)
            holdings[order.symbol] = Holding(quantity: quantity, averagePrice: average)
            cash -= value
        case .sell:
            if var existing = holdings[order.symbol] {
                existing.quantity -= order.quantity
                holdings[order.symbol] = existing.quantity == 0 ? nil : existing
            }
            cash += value
        }
        filled.status = "filled"
        filled.filledQuantity = order.quantity
        filled.filledAveragePrice = price
        return filled
    }

    /// Unknown symbols get a stable pseudo-random price so any ticker works in demo mode.
    private func price(for symbol: String) -> Decimal {
        if let price = prices[symbol] { return price }
        let seed = symbol.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 100_000 }
        let price = Decimal(20 + seed % 480) + Decimal(seed % 100) / 100
        prices[symbol] = price
        previousCloses[symbol] = Self.previousClose(for: symbol, price: price)
        return price
    }

    private func simulateLatency() async throws {
        try await Task.sleep(for: .milliseconds(Int.random(in: 120...320)))
    }

    private static func previousClose(for symbol: String, price: Decimal) -> Decimal {
        let seed = symbol.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let factor = 1 - Decimal(seed % 31 - 15) / 1000
        return (price * factor).rounded(scale: 2)
    }

    private static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Box–Muller transform: a standard normal sample.
    private static func gaussian() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1)
        let u2 = Double.random(in: 0..<1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

private extension ChartRange {
    var mockShape: (count: Int, step: TimeInterval, volatility: Double) {
        switch self {
        case .day: return (78, 300, 0.0012)
        case .week: return (65, 1_800, 0.003)
        case .month: return (154, 3_600, 0.005)
        case .threeMonths: return (63, 86_400, 0.012)
        case .year: return (252, 86_400, 0.014)
        }
    }
}
