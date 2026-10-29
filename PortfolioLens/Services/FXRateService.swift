import Foundation

/// Free ECB reference rates from Frankfurter (https://frankfurter.dev). No account or key needed.
actor FXRateService {
    private struct Response: Decodable {
        let base: String
        let date: String
        let rates: [String: Decimal]
    }

    private let session: URLSession
    private var cache: [String: CurrencyConverter] = [:]
    private static let cacheLifetime: TimeInterval = 3_600

    init(session: URLSession = .shared) {
        self.session = session
    }

    func converter(base: String) async -> CurrencyConverter {
        let code = base.uppercased()
        if let cached = cache[code], let asOf = cached.asOf,
           Date().timeIntervalSince(asOf) < Self.cacheLifetime {
            return cached
        }
        do {
            var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")!
            components.queryItems = [URLQueryItem(name: "base", value: code)]
            let (data, response) = try await session.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.invalidResponse }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let converter = CurrencyConverter(base: decoded.base, rates: decoded.rates, asOf: .now)
            cache[code] = converter
            return converter
        } catch {
            return cache[code] ?? FallbackRates.converter(base: code)
        }
    }
}
