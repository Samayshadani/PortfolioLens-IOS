import SwiftUI

struct OrdersView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case open = "Open"
        case history = "History"
        var id: String { rawValue }
    }

    @Environment(MarketStore.self) private var store
    @State private var filter: Filter = .open

    private var filteredOrders: [Order] {
        store.orders.filter { filter == .open ? $0.isOpen : !$0.isOpen }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredOrders) { order in
                    NavigationLink(value: order.symbol) {
                        OrderRow(order: order)
                    }
                    .swipeActions(edge: .trailing) {
                        if order.isOpen {
                            Button("Cancel", role: .destructive) {
                                Task { await store.cancelOrder(order) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .overlay {
                if filteredOrders.isEmpty {
                    ContentUnavailableView(
                        filter == .open ? "No open orders" : "No order history",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(filter == .open
                                          ? "Limit orders waiting to fill show up here. Swipe left to cancel."
                                          : "Filled, cancelled and rejected orders show up here."))
                }
            }
            .navigationTitle("Orders")
            .navigationDestination(for: String.self) { SymbolDetailView(symbol: $0) }
            .refreshable { await store.refreshAll() }
        }
    }
}

struct OrderRow: View {
    let order: Order

    private var statusColor: Color {
        switch order.status {
        case "filled": return Theme.gain
        case "canceled", "expired", "rejected": return .secondary
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(order.side.title.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 44)
                .padding(.vertical, 5)
                .background(order.side == .buy ? Theme.gain : Theme.loss, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(Format.quantity(order.quantity)) \(order.symbol)").font(.subheadline.weight(.semibold))
                Text(detailLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(order.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(order.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailLine: String {
        var parts = [order.typeName.replacingOccurrences(of: "_", with: " ").capitalized]
        if let limit = order.limitPrice { parts.append("limit \(Format.price(limit))") }
        if let filled = order.filledAveragePrice {
            parts.append("filled \(Format.quantity(order.filledQuantity)) @ \(Format.price(filled))")
        }
        parts.append(order.timeInForceName.uppercased())
        return parts.joined(separator: " · ")
    }
}
