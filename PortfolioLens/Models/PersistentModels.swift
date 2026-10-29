import Foundation
import SwiftData

@Model
final class WatchlistItem {
    @Attribute(.unique) var symbol: String
    var name: String
    var sortIndex: Int
    var addedAt: Date

    init(symbol: String, name: String, sortIndex: Int, addedAt: Date = .now) {
        self.symbol = symbol
        self.name = name
        self.sortIndex = sortIndex
        self.addedAt = addedAt
    }
}

enum AlertDirection: String, CaseIterable, Codable {
    case above, below

    func isTriggered(by price: Decimal, target: Decimal) -> Bool {
        self == .above ? price >= target : price <= target
    }

    var verb: String { self == .above ? "rises to or above" : "falls to or below" }
    var shortVerb: String { self == .above ? "above" : "below" }
    var icon: String { self == .above ? "arrow.up.circle.fill" : "arrow.down.circle.fill" }
}

@Model
final class PriceAlert {
    var id: UUID
    var symbol: String
    var targetPrice: Decimal
    var directionRaw: String
    var isActive: Bool
    var createdAt: Date
    var triggeredAt: Date?

    var direction: AlertDirection {
        get { AlertDirection(rawValue: directionRaw) ?? .above }
        set { directionRaw = newValue.rawValue }
    }

    init(symbol: String, targetPrice: Decimal, direction: AlertDirection) {
        self.id = UUID()
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.directionRaw = direction.rawValue
        self.isActive = true
        self.createdAt = .now
        self.triggeredAt = nil
    }
}

/// An asset held outside the broker (Indian stocks, mutual funds, deposits, gold, cash…)
/// so the Lens can show the user's real exposure, not just one brokerage account.
@Model
final class ManualHolding {
    var id: UUID
    var name: String
    var symbol: String
    var quantity: Decimal
    var unitPrice: Decimal
    var currencyCode: String
    var sector: String
    var assetClassRaw: String
    var updatedAt: Date

    var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .other }
        set { assetClassRaw = newValue.rawValue }
    }

    var marketValue: Decimal { quantity * unitPrice }

    var snapshot: HoldingSnapshot {
        HoldingSnapshot(
            id: "manual-\(id.uuidString)",
            symbol: symbol.isEmpty ? name : symbol,
            name: name,
            quantity: quantity,
            price: unitPrice,
            currency: currencyCode,
            sector: sector,
            assetClass: assetClass,
            source: .manual
        )
    }

    init(name: String, symbol: String, quantity: Decimal, unitPrice: Decimal,
         currencyCode: String, sector: String, assetClass: AssetClass) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.currencyCode = currencyCode
        self.sector = sector
        self.assetClassRaw = assetClass.rawValue
        self.updatedAt = .now
    }
}

enum WatchlistSeeder {
    private static let seededKey = "watchlist.seeded"
    static let defaultSymbols = ["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "TSLA", "SPY"]

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        for (index, symbol) in defaultSymbols.enumerated() {
            context.insert(WatchlistItem(symbol: symbol, name: SectorDirectory.info(for: symbol).name, sortIndex: index))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}
