import SwiftUI
import Charts

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

struct ChangePill: View {
    enum Style { case filled, subtle }

    let percent: Decimal?
    var style: Style = .filled

    var body: some View {
        let color = Theme.color(for: percent)
        Text(percent.map { Format.percent($0, signed: true) } ?? "—")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(style == .filled ? Color.white : color)
            .background(style == .filled ? color : color.opacity(0.14), in: Capsule())
            .contentTransition(.numericText())
            .animation(.snappy, value: percent)
    }
}

struct LivePriceText: View {
    let value: Decimal
    var font: Font = .body

    var body: some View {
        Text(Format.price(value))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: value.doubleValue))
            .animation(.snappy, value: value)
    }
}

struct SymbolBadge: View {
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        let color = Theme.stableColor(for: symbol)
        Text(String(symbol.prefix(symbol.count > 3 ? 2 : symbol.count)))
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct ConnectionIndicator: View {
    let state: ConnectionState

    private var color: Color {
        switch state {
        case .live: return Theme.gain
        case .connecting, .reconnecting: return .orange
        case .offline: return Theme.loss
        case .idle: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: state == .live)
            Text(state.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.fieldBackground, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Price stream \(state.label)")
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct WeightBar: View {
    let weight: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * min(max(weight, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.easeInOut, value: weight)
    }
}

struct DonutChart: View {
    let slices: [ExposureSlice]
    var innerRatio: CGFloat = 0.64

    var body: some View {
        Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
            SectorMark(
                angle: .value("Value", slice.value.doubleValue),
                innerRadius: .ratio(innerRatio),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(Theme.paletteColor(index))
        }
        .chartLegend(.hidden)
        .animation(.easeInOut, value: slices)
    }
}

struct NoticeBanner: View {
    let icon: String
    let text: String
    var tint: Color = Theme.accent
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct InputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .font(.body.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
