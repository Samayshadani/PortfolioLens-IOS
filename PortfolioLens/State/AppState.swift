import Foundation
import Observation
import SwiftData

enum DataSource: String, CaseIterable, Identifiable {
    case demo
    case alpacaPaper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: return "Demo (simulated)"
        case .alpacaPaper: return "Alpaca paper trading"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var dataSource: DataSource {
        didSet { defaults.set(dataSource.rawValue, forKey: Key.dataSource) }
    }

    var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: Key.baseCurrency) }
    }

    var biometricLockEnabled: Bool {
        didSet { defaults.set(biometricLockEnabled, forKey: Key.biometricLock) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dataSource = DataSource(rawValue: defaults.string(forKey: Key.dataSource) ?? "") ?? .demo
        baseCurrency = defaults.string(forKey: Key.baseCurrency) ?? "USD"
        biometricLockEnabled = defaults.bool(forKey: Key.biometricLock)
    }

    private enum Key {
        static let dataSource = "settings.dataSource"
        static let baseCurrency = "settings.baseCurrency"
        static let biometricLock = "settings.biometricLock"
    }
}

@MainActor
@Observable
final class FXStore {
    static let supportedCurrencies = [
        "USD", "INR", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD",
        "CNY", "HKD", "SGD", "SEK", "NZD", "KRW", "BRL", "ZAR"
    ]

    private(set) var converter: CurrencyConverter = FallbackRates.converter(base: "USD")
    private(set) var isLoading = false
    @ObservationIgnored private let service: FXRateService

    init(service: FXRateService) {
        self.service = service
    }

    func refresh(base: String) async {
        isLoading = true
        converter = await service.converter(base: base)
        isLoading = false
    }
}

@MainActor
@Observable
final class AlertCenter {
    struct TriggeredAlert: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    private(set) var lastTriggered: TriggeredAlert?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var activeAlerts: [PriceAlert] = []

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        let descriptor = FetchDescriptor<PriceAlert>(predicate: #Predicate<PriceAlert> { $0.isActive == true })
        activeAlerts = (try? context.fetch(descriptor)) ?? []
    }

    /// Direction is inferred: a target above the current price means "notify me when it rises".
    func addAlert(symbol: String, target: Decimal, currentPrice: Decimal?) {
        let direction: AlertDirection = (currentPrice.map { target >= $0 } ?? true) ? .above : .below
        context.insert(PriceAlert(symbol: symbol.uppercased(), targetPrice: target, direction: direction))
        save()
        Task { await NotificationService.shared.requestAuthorization() }
    }

    func delete(_ alert: PriceAlert) {
        context.delete(alert)
        save()
    }

    func reactivate(_ alert: PriceAlert, currentPrice: Decimal?) {
        if let currentPrice { alert.direction = alert.targetPrice >= currentPrice ? .above : .below }
        alert.isActive = true
        alert.triggeredAt = nil
        save()
    }

    func evaluate(symbol: String, price: Decimal) {
        var fired = false
        for alert in activeAlerts where alert.symbol == symbol
            && alert.direction.isTriggered(by: price, target: alert.targetPrice) {
            alert.isActive = false
            alert.triggeredAt = .now
            NotificationService.shared.postPriceAlert(symbol: symbol, price: price,
                                                      target: alert.targetPrice, direction: alert.direction)
            lastTriggered = TriggeredAlert(
                title: "\(symbol) is \(alert.direction.shortVerb) \(Format.price(alert.targetPrice))",
                message: "Last trade \(Format.price(price))")
            fired = true
        }
        if fired { save() }
    }

    func dismissBanner() {
        lastTriggered = nil
    }

    private func save() {
        try? context.save()
        reload()
    }
}

/// Builds and owns the app's long-lived objects.
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let settings: AppSettings
    let store: MarketStore
    let fx: FXStore
    let alerts: AlertCenter

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: WatchlistItem.self, PriceAlert.self, ManualHolding.self)
        } catch {
            fatalError("Couldn't open the SwiftData store: \(error)")
        }
        let settings = AppSettings()
        let alerts = AlertCenter(context: container.mainContext)
        let store = MarketStore(service: Self.makeService(for: settings.dataSource))
        store.alertCenter = alerts

        self.container = container
        self.settings = settings
        self.alerts = alerts
        self.store = store
        self.fx = FXStore(service: FXRateService())

        WatchlistSeeder.seedIfNeeded(container.mainContext)
        NotificationService.shared.configure()
    }

    /// Falls back to demo mode if Alpaca is selected but no keys are saved.
    static func makeService(for source: DataSource) -> BrokerageService {
        switch source {
        case .demo:
            return MockBrokerageService()
        case .alpacaPaper:
            guard let credentials = CredentialStore.loadAlpaca() else { return MockBrokerageService() }
            return AlpacaBrokerageService(credentials: credentials)
        }
    }

    func reloadDataSource() {
        store.replaceService(Self.makeService(for: settings.dataSource))
    }
}
