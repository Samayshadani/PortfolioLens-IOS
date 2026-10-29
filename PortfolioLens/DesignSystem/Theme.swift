import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.31, green: 0.36, blue: 0.96)
    static let accentDeep = Color(red: 0.17, green: 0.15, blue: 0.52)
    static let gain = Color(red: 0.10, green: 0.70, blue: 0.43)
    static let loss = Color(red: 0.93, green: 0.27, blue: 0.32)

    static let background = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let fieldBackground = Color(uiColor: .tertiarySystemFill)

    static let cornerRadius: CGFloat = 20

    static let palette: [Color] = [
        accent,
        Color(red: 0.00, green: 0.69, blue: 0.75),
        Color(red: 0.98, green: 0.62, blue: 0.16),
        Color(red: 0.85, green: 0.33, blue: 0.62),
        Color(red: 0.42, green: 0.75, blue: 0.30),
        Color(red: 0.58, green: 0.40, blue: 0.90),
        Color(red: 0.95, green: 0.42, blue: 0.30),
        Color(red: 0.55, green: 0.58, blue: 0.65)
    ]

    static func paletteColor(_ index: Int) -> Color {
        palette[index % palette.count]
    }

    static func stableColor(for text: String) -> Color {
        paletteColor(text.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
    }

    static func color(for value: Decimal?) -> Color {
        guard let value, value != 0 else { return .secondary }
        return value > 0 ? gain : loss
    }
}

extension RiskInsight.Severity {
    var icon: String {
        switch self {
        case .positive: return "checkmark.seal.fill"
        case .info: return "info.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .positive: return Theme.gain
        case .info: return .blue
        case .caution: return .orange
        case .warning: return Theme.loss
        }
    }
}
