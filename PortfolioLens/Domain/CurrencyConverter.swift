import Foundation

/// Converts amounts into a base currency. `rates` holds units of each currency per 1 unit of `base`
/// (the format returned by Frankfurter/ECB), so converting *into* base divides by the rate.
struct CurrencyConverter: Equatable {
    let base: String
    let rates: [String: Decimal]
    let asOf: Date?
    let isApproximate: Bool

    init(base: String, rates: [String: Decimal], asOf: Date? = nil, isApproximate: Bool = false) {
        let normalizedBase = base.uppercased()
        var normalized: [String: Decimal] = [:]
        for (code, rate) in rates { normalized[code.uppercased()] = rate }
        normalized[normalizedBase] = 1
        self.base = normalizedBase
        self.rates = normalized
        self.asOf = asOf
        self.isApproximate = isApproximate
    }

    static func identity(_ base: String) -> CurrencyConverter {
        CurrencyConverter(base: base, rates: [:], isApproximate: true)
    }

    /// Returns nil when no rate is known for `currency`, so callers can flag it instead of silently using 0.
    func convert(_ amount: Decimal, from currency: String) -> Decimal? {
        let code = currency.uppercased()
        if code == base { return amount }
        guard let rate = rates[code], rate != 0 else { return nil }
        return amount / rate
    }
}

/// Offline rates (units per 1 USD) used when the FX API can't be reached.
enum FallbackRates {
    static let perUSD: [String: Decimal] = [
        "USD": 1, "EUR": Decimal(string: "0.86")!, "GBP": Decimal(string: "0.75")!,
        "INR": Decimal(string: "88.5")!, "JPY": 150, "CHF": Decimal(string: "0.80")!,
        "CAD": Decimal(string: "1.39")!, "AUD": Decimal(string: "1.52")!, "CNY": Decimal(string: "7.12")!,
        "HKD": Decimal(string: "7.78")!, "SGD": Decimal(string: "1.30")!, "SEK": Decimal(string: "9.5")!,
        "NZD": Decimal(string: "1.73")!, "KRW": 1420, "BRL": Decimal(string: "5.4")!, "ZAR": Decimal(string: "17.5")!
    ]

    static func converter(base: String) -> CurrencyConverter {
        let code = base.uppercased()
        guard let baseRate = perUSD[code], baseRate != 0 else { return .identity(code) }
        var rates: [String: Decimal] = [:]
        for (currency, usdRate) in perUSD { rates[currency] = usdRate / baseRate }
        return CurrencyConverter(base: code, rates: rates, asOf: nil, isApproximate: true)
    }
}
