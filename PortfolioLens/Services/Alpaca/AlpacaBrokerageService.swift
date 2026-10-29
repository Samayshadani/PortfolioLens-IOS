import Foundation

struct AlpacaCredentials: Equatable {
    let keyID: String
    let secretKey: String
}

enum AlpacaEndpoints {
    static let trading = URL(string: "https://paper-api.alpaca.markets/v2")!
    static let marketData = URL(string: "https://data.alpaca.markets/v2")!
    /// IEX is the feed included in Alpaca's free plan.
    static let stream = URL(string: "wss://stream.data.alpaca.markets/v2/iex")!
    static let feed = "iex"
}

final class AlpacaBrokerageService: BrokerageService {
    let displayName = "Alpaca Paper"
    let isSimulated = false

    private let credentials: AlpacaCredentials
    private let session: URLSession
    private let http: HTTPClient

    init(credentials: AlpacaCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
        self.http = HTTPClient(session: session)
    }

    // MARK: Trading API

    func fetchAccount() async throws -> Account {
        let request = try makeRequest(AlpacaEndpoints.trading, path: "account")
        return AlpacaMapper.account(try await http.decode(AlpacaAccountDTO.self, from: request))
    }

    func fetchPositions() async throws -> [Position] {
        let request = try makeRequest(AlpacaEndpoints.trading, path: "positions")
        return try await http.decode([AlpacaPositionDTO].self, from: request).map(AlpacaMapper.position)
    }

    func fetchOrders() async throws -> [Order] {
        let request = try makeRequest(AlpacaEndpoints.trading, path: "orders", query: [
            URLQueryItem(name: "status", value: "all"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "direction", value: "desc")
        ])
        return try await http.decode([AlpacaOrderDTO].self, from: request).map(AlpacaMapper.order)
    }

    func placeOrder(_ orderRequest: OrderRequest) async throws -> Order {
        let body = try JSONEncoder.alpaca.encode(AlpacaMapper.payload(for: orderRequest))
        let request = try makeRequest(AlpacaEndpoints.trading, path: "orders", method: "POST", body: body)
        return AlpacaMapper.order(try await http.decode(AlpacaOrderDTO.self, from: request))
    }

    func cancelOrder(id: String) async throws {
        let request = try makeRequest(AlpacaEndpoints.trading, path: "orders/\(id)", method: "DELETE")
        try await http.data(for: request)
    }

    func asset(symbol: String) async throws -> AssetInfo {
        let request = try makeRequest(AlpacaEndpoints.trading, path: "assets/\(symbol.uppercased())")
        do {
            return AlpacaMapper.asset(try await http.decode(AlpacaAssetDTO.self, from: request))
        } catch APIError.notFound {
            throw APIError.notFound("\(symbol.uppercased()) isn't a symbol Alpaca recognises.")
        }
    }

    // MARK: Market data API

    func fetchSnapshots(symbols: [String]) async throws -> [String: Quote] {
        guard !symbols.isEmpty else { return [:] }
        let request = try makeRequest(AlpacaEndpoints.marketData, path: "stocks/snapshots", query: [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "feed", value: AlpacaEndpoints.feed)
        ])
        let response = try await http.decode([String: AlpacaSnapshotDTO?].self, from: request)
        var quotes: [String: Quote] = [:]
        for (symbol, snapshot) in response {
            if let snapshot, let quote = AlpacaMapper.quote(symbol: symbol, snapshot: snapshot) {
                quotes[symbol] = quote
            }
        }
        return quotes
    }

    func fetchBars(symbol: String, range: ChartRange) async throws -> [PriceBar] {
        let start = Date().addingTimeInterval(-range.lookback)
        let request = try makeRequest(AlpacaEndpoints.marketData, path: "stocks/\(symbol.uppercased())/bars", query: [
            URLQueryItem(name: "timeframe", value: range.alpacaTimeframe),
            URLQueryItem(name: "start", value: AlpacaDate.format(start)),
            URLQueryItem(name: "limit", value: "1000"),
            URLQueryItem(name: "adjustment", value: "split"),
            URLQueryItem(name: "feed", value: AlpacaEndpoints.feed)
        ])
        let bars = (try await http.decode(AlpacaBarsResponse.self, from: request).bars ?? []).map(AlpacaMapper.bar)

        // "1D" asks for a few days so weekends still show data, then keeps only the latest session.
        guard range == .day, let last = bars.last else { return bars }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return bars.filter { calendar.isDate($0.time, inSameDayAs: last.time) }
    }

    // MARK: WebSocket price stream

    func priceStream(symbols: [String]) -> AsyncThrowingStream<PriceStreamEvent, Error> {
        let credentials = self.credentials
        let socket = session.webSocketTask(with: AlpacaEndpoints.stream)

        return AsyncThrowingStream { continuation in
            let task = Task {
                let decoder = JSONDecoder.alpaca
                socket.resume()
                do {
                    while !Task.isCancelled {
                        let data: Data
                        switch try await socket.receive() {
                        case .data(let payload): data = payload
                        case .string(let text): data = Data(text.utf8)
                        @unknown default: continue
                        }

                        for message in try decoder.decode([AlpacaStreamMessage].self, from: data) {
                            switch (message.type, message.message) {
                            case ("success", "connected"):
                                try await socket.send(.string(Self.json(["action": "auth", "key": credentials.keyID, "secret": credentials.secretKey])))
                            case ("success", "authenticated"):
                                try await socket.send(.string(Self.json(["action": "subscribe", "trades": symbols])))
                            case ("subscription", _):
                                continuation.yield(.connected)
                            case ("t", _):
                                if let symbol = message.symbol, let price = message.price {
                                    let time = message.timestamp.flatMap(AlpacaDate.parse) ?? .now
                                    continuation.yield(.tick(PriceTick(symbol: symbol, price: price, timestamp: time)))
                                }
                            case ("error", _):
                                throw StreamError.server(code: message.code ?? 0, message: message.message ?? "Unknown error")
                            default:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                socket.cancel(with: .goingAway, reason: nil)
            }
            continuation.onTermination = { _ in
                task.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    // MARK: Helpers

    private func makeRequest(_ base: URL, path: String, query: [URLQueryItem] = [],
                             method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue(credentials.keyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(credentials.secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}

private extension ChartRange {
    var alpacaTimeframe: String {
        switch self {
        case .day: return "5Min"
        case .week: return "30Min"
        case .month: return "1Hour"
        case .threeMonths, .year: return "1Day"
        }
    }

    var lookback: TimeInterval {
        let day: TimeInterval = 86_400
        switch self {
        case .day: return 4 * day
        case .week: return 7 * day
        case .month: return 31 * day
        case .threeMonths: return 92 * day
        case .year: return 366 * day
        }
    }
}
