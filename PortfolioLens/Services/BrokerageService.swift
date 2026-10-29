import Foundation

/// Everything the app needs from a broker. `AlpacaBrokerageService` talks to the real
/// paper-trading API; `MockBrokerageService` simulates a market so the app works offline.
protocol BrokerageService: AnyObject {
    var displayName: String { get }
    var isSimulated: Bool { get }

    func fetchAccount() async throws -> Account
    func fetchPositions() async throws -> [Position]
    func fetchOrders() async throws -> [Order]
    func placeOrder(_ request: OrderRequest) async throws -> Order
    func cancelOrder(id: String) async throws
    func fetchSnapshots(symbols: [String]) async throws -> [String: Quote]
    func fetchBars(symbol: String, range: ChartRange) async throws -> [PriceBar]
    func asset(symbol: String) async throws -> AssetInfo
    func priceStream(symbols: [String]) -> AsyncThrowingStream<PriceStreamEvent, Error>
}

enum StreamError: LocalizedError {
    case server(code: Int, message: String)

    /// Bad keys, too many symbols or a missing data plan won't fix themselves by reconnecting.
    var isRetryable: Bool {
        switch self {
        case .server(let code, _): return ![402, 405, 409].contains(code)
        }
    }

    var errorDescription: String? {
        switch self {
        case .server(let code, let message):
            switch code {
            case 402: return "Alpaca rejected your keys for live prices."
            case 405: return "Too many symbols for the free plan (max 30)."
            case 406: return "Another device or app is already streaming with these keys. The free plan allows one connection."
            case 409: return "Your Alpaca data plan doesn't include this feed."
            default: return "Price stream error \(code): \(message)"
            }
        }
    }
}
