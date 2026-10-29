import Foundation
import Observation

enum ConnectionState: Equatable {
    case idle
    case connecting
    case live
    case reconnecting(attempt: Int)
    case offline(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .live: return "Live"
        case .reconnecting: return "Reconnecting"
        case .offline: return "Offline"
        }
    }
}

/// Single source of truth for account, positions, orders and live quotes.
/// REST data is polled; prices stream over a WebSocket and are coalesced before
/// being published so a burst of trades doesn't re-render the UI hundreds of times.
@MainActor
@Observable
final class MarketStore {
    private(set) var account: Account?
    private(set) var positions: [Position] = []
    private(set) var orders: [Order] = []
    private(set) var quotes: [String: Quote] = [:]
    private(set) var connection: ConnectionState = .idle
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var serviceName: String
    private(set) var isSimulated: Bool
    var errorMessage: String?

    @ObservationIgnored weak var alertCenter: AlertCenter?
    @ObservationIgnored private var service: BrokerageService
    @ObservationIgnored private var watchlistSymbols: [String] = []
    @ObservationIgnored private var streamingSymbols: [String] = []
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTicks: [String: PriceTick] = [:]
    @ObservationIgnored private var isRunning = false

    /// Alpaca's free IEX stream allows 30 symbols.
    static let maxStreamSymbols = 30
    private static let pollInterval: Duration = .seconds(20)
    private static let tickFlushInterval: Duration = .milliseconds(250)

    init(service: BrokerageService) {
        self.service = service
        self.serviceName = service.displayName
        self.isSimulated = service.isSimulated
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        streamTask?.cancel()
        streamTask = nil
        streamingSymbols = []
        connection = .idle
    }

    func replaceService(_ newService: BrokerageService) {
        stop()
        service = newService
        serviceName = newService.displayName
        isSimulated = newService.isSimulated
        account = nil
        positions = []
        orders = []
        quotes = [:]
        errorMessage = nil
        start()
    }

    func setWatchlist(_ symbols: [String]) {
        watchlistSymbols = symbols
        guard isRunning else { return }
        Task { await syncSubscriptions() }
    }

    // MARK: REST data

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let service = self.service
        do {
            async let accountRequest = service.fetchAccount()
            async let positionsRequest = service.fetchPositions()
            async let ordersRequest = service.fetchOrders()
            let (account, positions, orders) = try await (accountRequest, positionsRequest, ordersRequest)
            guard service === self.service else { return }
            self.account = account
            self.positions = positions.sorted { $0.symbol < $1.symbol }
            self.orders = orders
            lastRefresh = .now
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        await syncSubscriptions()
    }

    func quote(for symbol: String) async -> Quote? {
        let symbol = symbol.uppercased()
        if let quote = quotes[symbol] { return quote }
        await loadSnapshots(for: [symbol])
        return quotes[symbol]
    }

    func bars(for symbol: String, range: ChartRange) async throws -> [PriceBar] {
        try await service.fetchBars(symbol: symbol, range: range)
    }

    func lookupAsset(_ symbol: String) async throws -> AssetInfo {
        try await service.asset(symbol: symbol)
    }

    func position(for symbol: String) -> Position? {
        positions.first { $0.symbol == symbol }
    }

    // MARK: Orders

    func placeOrder(_ request: OrderRequest) async throws -> Order {
        let order = try await service.placeOrder(request)
        orders.insert(order, at: 0)
        // Give the broker a moment to fill, then pull fresh positions and cash.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            await self?.refreshAll()
        }
        return order
    }

    func cancelOrder(_ order: Order) async {
        do {
            try await service.cancelOrder(id: order.id)
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Streaming

    private func syncSubscriptions() async {
        let positionSymbols = positions.filter(\.isStreamable).map(\.symbol)
        var seen = Set<String>()
        let symbols = Array((watchlistSymbols + positionSymbols)
            .filter { seen.insert($0).inserted }
            .prefix(Self.maxStreamSymbols))

        let missing = symbols.filter { quotes[$0] == nil }
        if !missing.isEmpty { await loadSnapshots(for: missing) }

        guard isRunning else { return }
        if Set(symbols) != Set(streamingSymbols) || streamTask == nil {
            startStream(symbols)
        }
    }

    private func loadSnapshots(for symbols: [String]) async {
        let service = self.service
        do {
            let snapshots = try await service.fetchSnapshots(symbols: symbols)
            guard service === self.service else { return }
            for (symbol, quote) in snapshots { quotes[symbol] = quote }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startStream(_ symbols: [String]) {
        let hadPreviousStream = streamTask != nil
        streamTask?.cancel()
        streamingSymbols = symbols
        guard !symbols.isEmpty else {
            streamTask = nil
            connection = .idle
            return
        }

        let service = self.service
        streamTask = Task { [weak self] in
            // The free plan allows one socket, so let the previous one close first.
            if hadPreviousStream { try? await Task.sleep(for: .seconds(1)) }
            var attempt = 0
            while !Task.isCancelled {
                self?.connection = attempt == 0 ? .connecting : .reconnecting(attempt: attempt)
                do {
                    for try await event in service.priceStream(symbols: symbols) {
                        switch event {
                        case .connected:
                            attempt = 0
                            self?.connection = .live
                        case .tick(let tick):
                            self?.enqueue(tick)
                        }
                    }
                } catch let error as StreamError where !error.isRetryable {
                    if !Task.isCancelled { self?.connection = .offline(error.localizedDescription) }
                    return
                } catch {
                    // Network drop or server hiccup: fall through to the backoff below.
                }
                if Task.isCancelled { return }
                attempt += 1
                let delay = min(30, 1 << min(attempt, 5))
                self?.connection = .reconnecting(attempt: attempt)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func enqueue(_ tick: PriceTick) {
        pendingTicks[tick.symbol] = tick
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.tickFlushInterval)
            self?.flushTicks()
        }
    }

    private func flushTicks() {
        flushTask = nil
        let ticks = pendingTicks
        pendingTicks = [:]
        guard !ticks.isEmpty else { return }

        var updated = quotes
        for tick in ticks.values {
            if var quote = updated[tick.symbol] {
                quote.price = tick.price
                quote.updatedAt = tick.timestamp
                updated[tick.symbol] = quote
            } else {
                let previousClose = positions.first { $0.symbol == tick.symbol }?.lastDayPrice
                updated[tick.symbol] = Quote(symbol: tick.symbol, price: tick.price,
                                             previousClose: previousClose, updatedAt: tick.timestamp)
            }
            alertCenter?.evaluate(symbol: tick.symbol, price: tick.price)
        }
        quotes = updated
    }
}
