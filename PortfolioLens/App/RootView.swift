import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MarketStore.self) private var store
    @Environment(FXStore.self) private var fx
    @Environment(AlertCenter.self) private var alerts
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WatchlistItem.sortIndex) private var watchlist: [WatchlistItem]
    @State private var isLocked = false
    @State private var hasLaunched = false

    var body: some View {
        TabView {
            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.pie.fill") }
            WatchlistView()
                .tabItem { Label("Markets", systemImage: "chart.line.uptrend.xyaxis") }
            LensView()
                .tabItem { Label("Lens", systemImage: "scope") }
            OrdersView()
                .tabItem { Label("Orders", systemImage: "list.bullet.rectangle.portrait") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) { alertBanner }
        .animation(.spring(duration: 0.4), value: alerts.lastTriggered)
        .overlay {
            if isLocked {
                LockView { withAnimation(.easeOut(duration: 0.25)) { isLocked = false } }
                    .transition(.opacity)
            }
        }
        .task {
            guard !hasLaunched else { return }
            hasLaunched = true
            isLocked = settings.biometricLockEnabled
            store.setWatchlist(watchlist.map(\.symbol))
            store.start()
            await fx.refresh(base: settings.baseCurrency)
        }
        .onChange(of: watchlist.map(\.symbol)) { _, symbols in
            store.setWatchlist(symbols)
        }
        .onChange(of: settings.baseCurrency) { _, base in
            Task { await fx.refresh(base: base) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if settings.biometricLockEnabled { isLocked = true }
                store.stop()
            case .active:
                if hasLaunched { store.start() }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var alertBanner: some View {
        if let triggered = alerts.lastTriggered {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(triggered.title).font(.subheadline.weight(.semibold))
                    Text(triggered.message).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { alerts.dismissBanner() }
            .task(id: triggered.id) {
                try? await Task.sleep(for: .seconds(4))
                alerts.dismissBanner()
            }
        }
    }
}
