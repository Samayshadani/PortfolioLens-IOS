import SwiftUI
import UIKit

struct OrderTicketView: View {
    let symbol: String
    @Environment(MarketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var side: OrderSide
    @State private var orderType: OrderType = .market
    @State private var timeInForce: TimeInForce = .day
    @State private var quantityText: String
    @State private var limitText = ""
    @State private var isSubmitting = false
    @State private var isConfirming = false
    @State private var errorMessage: String?
    @State private var placedOrder: Order?

    init(symbol: String, side: OrderSide, quantity: Decimal? = nil) {
        self.symbol = symbol.uppercased()
        _side = State(initialValue: side)
        _quantityText = State(initialValue: quantity.map(Format.plainNumber) ?? "")
    }

    private var quote: Quote? { store.quotes[symbol] }
    private var currency: String { store.account?.currency ?? "USD" }
    private var quantity: Decimal? { Decimal.parseUserInput(quantityText) }
    private var limitPrice: Decimal? { Decimal.parseUserInput(limitText) }
    private var heldShares: Decimal { store.position(for: symbol)?.quantity ?? 0 }

    private var referencePrice: Decimal? {
        orderType == .limit ? limitPrice : quote?.price
    }

    private var estimatedValue: Decimal? {
        guard let quantity, let referencePrice else { return nil }
        return quantity * referencePrice
    }

    /// Problems that block submission.
    private var validationIssue: String? {
        guard let quantity, quantity > 0 else { return "Enter a quantity greater than zero." }
        if orderType == .limit {
            guard let limitPrice, limitPrice > 0 else { return "Enter a limit price." }
        }
        if !quantity.isWholeNumber, timeInForce != .day {
            return "Fractional-share orders must use Day time in force."
        }
        if side == .buy, let estimatedValue, let buyingPower = store.account?.buyingPower, estimatedValue > buyingPower {
            return "This order exceeds your buying power of \(Format.currency(buyingPower, code: currency))."
        }
        return nil
    }

    /// Risky but allowed.
    private var warning: String? {
        guard side == .sell, let quantity, quantity > heldShares else { return nil }
        return heldShares > 0
            ? "You hold \(Format.quantity(heldShares)) shares. Selling more opens a short position."
            : "You don't own \(symbol). This sale would open a short position."
    }

    var body: some View {
        NavigationStack {
            Group {
                if let placedOrder {
                    OrderConfirmationView(order: placedOrder, currency: currency) { dismiss() }
                } else {
                    form
                }
            }
            .navigationTitle(placedOrder == nil ? "\(side.title) \(symbol)" : "Order sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { _ = await store.quote(for: symbol) }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    SymbolBadge(symbol: symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(symbol).font(.headline)
                        Text(SectorDirectory.info(for: symbol).name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let quote {
                        VStack(alignment: .trailing, spacing: 4) {
                            LivePriceText(value: quote.price, font: .headline)
                            ChangePill(percent: quote.changePercent, style: .subtle)
                        }
                    } else {
                        ProgressView()
                    }
                }
                Picker("Side", selection: $side) {
                    ForEach(OrderSide.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Order") {
                Picker("Order type", selection: $orderType) {
                    ForEach(OrderType.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Quantity") {
                    TextField("0", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                if orderType == .limit {
                    LabeledContent("Limit price") {
                        TextField(quote.map { Format.plainNumber($0.price) } ?? "0.00", text: $limitText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Picker("Time in force", selection: $timeInForce) {
                    ForEach(TimeInForce.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Estimate") {
                LabeledContent(side == .buy ? "Estimated cost" : "Estimated proceeds",
                               value: estimatedValue.map { Format.currency($0, code: currency) } ?? "—")
                if let buyingPower = store.account?.buyingPower {
                    LabeledContent("Buying power", value: Format.currency(buyingPower, code: currency))
                }
                LabeledContent("Shares after fill") {
                    let after = heldShares + (side == .buy ? 1 : -1) * (quantity ?? 0)
                    Text("\(Format.quantity(heldShares)) → \(Format.quantity(after))").monospacedDigit()
                }
            }

            if let validationIssue, !quantityText.isEmpty {
                Section { Label(validationIssue, systemImage: "exclamationmark.circle").foregroundStyle(Theme.loss).font(.footnote) }
            }
            if let warning {
                Section { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "xmark.octagon").foregroundStyle(Theme.loss) }
            }

            Section {
                NavigationLink {
                    WhatIfView(initialSymbol: symbol, side: side, quantity: quantity, showsOrderButton: false)
                        .navigationTitle("Portfolio impact")
                } label: {
                    Label("Preview portfolio impact", systemImage: "scope")
                }
            } footer: {
                Text(store.isSimulated
                     ? "Demo mode: orders fill instantly against simulated prices."
                     : "Paper trading: orders go to Alpaca's simulated exchange. No real money is used.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { submitBar }
        .confirmationDialog(confirmationTitle, isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Place order") { Task { await submit() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let estimatedValue {
                Text("Estimated \(side == .buy ? "cost" : "proceeds"): \(Format.currency(estimatedValue, code: currency))")
            }
        }
    }

    private var confirmationTitle: String {
        let amount = Format.quantity(quantity ?? 0)
        let priceText = orderType == .limit ? "at \(Format.price(limitPrice ?? 0)) limit" : "at market"
        return "\(side.title) \(amount) \(symbol) \(priceText)?"
    }

    private var submitBar: some View {
        Button { isConfirming = true } label: {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSubmitting ? "Submitting…" : "Review \(side.title.lowercased()) order")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .tint(side == .buy ? Theme.gain : Theme.loss)
        .disabled(validationIssue != nil || isSubmitting)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func submit() async {
        guard let quantity else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let request = OrderRequest(
            symbol: symbol, quantity: quantity, side: side, type: orderType,
            timeInForce: timeInForce, limitPrice: orderType == .limit ? limitPrice : nil)
        do {
            let order = try await store.placeOrder(request)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring) { placedOrder = order }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}

private struct OrderConfirmationView: View {
    let order: Order
    let currency: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: order.status == "filled" ? "checkmark.circle.fill" : "paperplane.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(order.side == .buy ? Theme.gain : Theme.loss)
                .symbolEffect(.bounce, value: order.id)
            VStack(spacing: 6) {
                Text("\(order.side.title) \(Format.quantity(order.quantity)) \(order.symbol)")
                    .font(.title2.bold())
                Text("Status: \(order.statusTitle)").foregroundStyle(.secondary)
                if let price = order.filledAveragePrice {
                    Text("Filled at \(Format.currency(price, code: currency))").foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onDone) {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .frame(maxWidth: .infinity)
    }
}
