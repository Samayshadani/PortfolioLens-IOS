import Foundation

struct Quote: Equatable {
    let symbol: String
    var price: Decimal
    var previousClose: Decimal?
    var updatedAt: Date

    var change: Decimal? { previousClose.map { price - $0 } }

    var changePercent: Decimal? {
        guard let previousClose, previousClose != 0 else { return nil }
        return (price - previousClose) / previousClose
    }
}

struct PriceTick: Equatable {
    let symbol: String
    let price: Decimal
    let timestamp: Date
}

enum PriceStreamEvent {
    case connected
    case tick(PriceTick)
}

struct PriceBar: Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let open: Decimal
    let high: Decimal
    let low: Decimal
    let close: Decimal
    let volume: Int
}

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"

    var id: String { rawValue }
}

struct AssetInfo: Equatable {
    let symbol: String
    let name: String
    let exchange: String
    let tradable: Bool
    let fractionable: Bool
}

struct Account: Equatable {
    let id: String
    let accountNumber: String
    let currency: String
    let status: String
    let cash: Decimal
    let equity: Decimal
    let lastEquity: Decimal
    let buyingPower: Decimal
    let longMarketValue: Decimal
    let maintenanceMargin: Decimal
}

struct Position: Identifiable, Equatable {
    var id: String { symbol }
    let symbol: String
    /// Signed: negative for short positions.
    let quantity: Decimal
    let averageEntryPrice: Decimal
    let currentPrice: Decimal
    let lastDayPrice: Decimal
    let assetClass: String

    var isStreamable: Bool { assetClass == "us_equity" }
    var isCrypto: Bool { assetClass == "crypto" }
}

enum OrderSide: String, CaseIterable, Identifiable {
    case buy, sell
    var id: String { rawValue }
    var title: String { self == .buy ? "Buy" : "Sell" }
}

enum OrderType: String, CaseIterable, Identifiable {
    case market, limit
    var id: String { rawValue }
    var title: String { self == .market ? "Market" : "Limit" }
}

enum TimeInForce: String, CaseIterable, Identifiable {
    case day, gtc
    var id: String { rawValue }
    var title: String { self == .day ? "Day" : "Good till cancelled" }
}

struct OrderRequest: Equatable {
    let symbol: String
    let quantity: Decimal
    let side: OrderSide
    let type: OrderType
    let timeInForce: TimeInForce
    let limitPrice: Decimal?
}

struct Order: Identifiable, Equatable {
    let id: String
    let symbol: String
    var quantity: Decimal
    var filledQuantity: Decimal
    var filledAveragePrice: Decimal?
    let side: OrderSide
    let typeName: String
    let timeInForceName: String
    let limitPrice: Decimal?
    var status: String
    let createdAt: Date

    private static let openStatuses: Set<String> = [
        "new", "accepted", "pending_new", "partially_filled", "accepted_for_bidding", "held", "pending_replace"
    ]

    var isOpen: Bool { Self.openStatuses.contains(status) }
    var statusTitle: String { status.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum AssetClass: String, CaseIterable, Identifiable, Codable {
    case equity, etf, bond, commodity, crypto, cash, realEstate, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equity: return "Stocks"
        case .etf: return "ETFs & funds"
        case .bond: return "Bonds"
        case .commodity: return "Commodities"
        case .crypto: return "Crypto"
        case .cash: return "Cash"
        case .realEstate: return "Real estate"
        case .other: return "Other"
        }
    }
}
