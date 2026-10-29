import Foundation

// Raw Alpaca payloads. Numbers on the trading API arrive as strings, so they're
// parsed into Decimal by AlpacaMapper rather than lossy Doubles.

struct AlpacaAccountDTO: Decodable {
    let id: String
    let accountNumber: String?
    let status: String?
    let currency: String?
    let cash: String?
    let equity: String?
    let lastEquity: String?
    let buyingPower: String?
    let longMarketValue: String?
    let maintenanceMargin: String?
}

struct AlpacaPositionDTO: Decodable {
    let symbol: String
    let qty: String?
    let side: String?
    let avgEntryPrice: String?
    let currentPrice: String?
    let lastdayPrice: String?
    let assetClass: String?
}

struct AlpacaOrderDTO: Decodable {
    let id: String
    let symbol: String
    let qty: String?
    let filledQty: String?
    let filledAvgPrice: String?
    let side: String
    let type: String?
    let timeInForce: String?
    let limitPrice: String?
    let status: String
    let createdAt: Date
}

struct AlpacaOrderPayload: Encodable {
    let symbol: String
    let qty: String
    let side: String
    let type: String
    let timeInForce: String
    let limitPrice: String?
}

struct AlpacaAssetDTO: Decodable {
    let symbol: String
    let name: String?
    let exchange: String?
    let tradable: Bool?
    let fractionable: Bool?
}

struct AlpacaTradeDTO: Decodable {
    let p: Decimal
    let t: Date
}

struct AlpacaBarDTO: Decodable {
    let t: Date
    let o: Decimal
    let h: Decimal
    let l: Decimal
    let c: Decimal
    let v: Double
}

struct AlpacaSnapshotDTO: Decodable {
    let latestTrade: AlpacaTradeDTO?
    let dailyBar: AlpacaBarDTO?
    let prevDailyBar: AlpacaBarDTO?
}

struct AlpacaBarsResponse: Decodable {
    let bars: [AlpacaBarDTO]?
    let nextPageToken: String?
}

/// One element of the arrays the market-data WebSocket sends.
struct AlpacaStreamMessage: Decodable {
    let type: String
    let symbol: String?
    let price: Decimal?
    let timestamp: String?
    let message: String?
    let code: Int?

    enum CodingKeys: String, CodingKey {
        case type = "T"
        case symbol = "S"
        case price = "p"
        case timestamp = "t"
        case message = "msg"
        case code
    }
}

enum AlpacaMapper {
    static func account(_ dto: AlpacaAccountDTO) -> Account {
        Account(
            id: dto.id,
            accountNumber: dto.accountNumber ?? "—",
            currency: dto.currency ?? "USD",
            status: dto.status ?? "UNKNOWN",
            cash: Decimal(apiString: dto.cash) ?? 0,
            equity: Decimal(apiString: dto.equity) ?? 0,
            lastEquity: Decimal(apiString: dto.lastEquity) ?? 0,
            buyingPower: Decimal(apiString: dto.buyingPower) ?? 0,
            longMarketValue: Decimal(apiString: dto.longMarketValue) ?? 0,
            maintenanceMargin: Decimal(apiString: dto.maintenanceMargin) ?? 0
        )
    }

    static func position(_ dto: AlpacaPositionDTO) -> Position {
        let rawQuantity = Decimal(apiString: dto.qty) ?? 0
        let quantity = dto.side == "short" && rawQuantity > 0 ? -rawQuantity : rawQuantity
        let average = Decimal(apiString: dto.avgEntryPrice) ?? 0
        let current = Decimal(apiString: dto.currentPrice) ?? average
        return Position(
            symbol: dto.symbol,
            quantity: quantity,
            averageEntryPrice: average,
            currentPrice: current,
            lastDayPrice: Decimal(apiString: dto.lastdayPrice) ?? current,
            assetClass: dto.assetClass ?? "us_equity"
        )
    }

    static func order(_ dto: AlpacaOrderDTO) -> Order {
        Order(
            id: dto.id,
            symbol: dto.symbol,
            quantity: Decimal(apiString: dto.qty) ?? 0,
            filledQuantity: Decimal(apiString: dto.filledQty) ?? 0,
            filledAveragePrice: Decimal(apiString: dto.filledAvgPrice),
            side: OrderSide(rawValue: dto.side) ?? .buy,
            typeName: dto.type ?? "market",
            timeInForceName: dto.timeInForce ?? "day",
            limitPrice: Decimal(apiString: dto.limitPrice),
            status: dto.status,
            createdAt: dto.createdAt
        )
    }

    static func asset(_ dto: AlpacaAssetDTO) -> AssetInfo {
        let name = dto.name?.isEmpty == false ? dto.name! : SectorDirectory.info(for: dto.symbol).name
        return AssetInfo(
            symbol: dto.symbol,
            name: name,
            exchange: dto.exchange ?? "",
            tradable: dto.tradable ?? false,
            fractionable: dto.fractionable ?? false
        )
    }

    static func quote(symbol: String, snapshot: AlpacaSnapshotDTO) -> Quote? {
        guard let price = snapshot.latestTrade?.p ?? snapshot.dailyBar?.c else { return nil }
        return Quote(
            symbol: symbol,
            price: price,
            previousClose: snapshot.prevDailyBar?.c,
            updatedAt: snapshot.latestTrade?.t ?? .now
        )
    }

    static func bar(_ dto: AlpacaBarDTO) -> PriceBar {
        PriceBar(time: dto.t, open: dto.o, high: dto.h, low: dto.l, close: dto.c, volume: Int(dto.v))
    }

    static func payload(for request: OrderRequest) -> AlpacaOrderPayload {
        AlpacaOrderPayload(
            symbol: request.symbol.uppercased(),
            qty: Format.plainNumber(request.quantity),
            side: request.side.rawValue,
            type: request.type.rawValue,
            timeInForce: request.timeInForce.rawValue,
            limitPrice: request.type == .limit ? request.limitPrice.map(Format.plainNumber) : nil
        )
    }
}
