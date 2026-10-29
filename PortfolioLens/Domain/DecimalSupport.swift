import Foundation

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    var isWholeNumber: Bool { self == rounded(scale: 0, mode: .down) }

    /// Parses numbers sent by APIs, which always use "." as the decimal separator.
    init?(apiString: String?) {
        guard let apiString, !apiString.isEmpty,
              let value = Decimal(string: apiString, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        self = value
    }

    /// Parses what a user typed, accepting the device locale's decimal separator as well as ".".
    /// Strict on purpose: "12abc" is rejected rather than read as 12.
    static func parseUserInput(_ text: String) -> Decimal? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = Locale.current.decimalSeparator, separator != "." {
            normalized = normalized.replacingOccurrences(of: separator, with: ".")
        }
        guard normalized.range(of: #"^-?(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(apiString: normalized)
    }
}

enum Format {
    static func currency(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(2)))
    }

    static func signedCurrency(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(2)).sign(strategy: .always()))
    }

    static func price(_ value: Decimal) -> String {
        let digits = abs(value) < 1 ? 4 : 2
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func percent(_ value: Decimal, signed: Bool = false) -> String {
        if signed {
            return value.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
        }
        return value.formatted(.percent.precision(.fractionLength(1)))
    }

    static func quantity(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }

    /// Locale-independent representation used for API payloads and pre-filled text fields.
    static func plainNumber(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
