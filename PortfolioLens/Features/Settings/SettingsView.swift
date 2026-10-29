import SwiftUI
import SwiftData

struct SettingsView: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(AppSettings.self) private var settings
    @Environment(MarketStore.self) private var store
    @State private var keyID = ""
    @State private var secretKey = ""
    @State private var hasSavedKeys = CredentialStore.loadAlpaca() != nil
    @State private var testState: TestState = .idle
    @State private var lockEnabled = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker("Data source", selection: $settings.dataSource) {
                        ForEach(DataSource.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Connected to", value: store.serviceName)
                    if settings.dataSource == .alpacaPaper && !hasSavedKeys {
                        Label("Add your Alpaca keys below. Until then the app stays in demo mode.", systemImage: "key")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Market data & trading")
                }

                alpacaSection

                Section("Display") {
                    Picker("Base currency", selection: $settings.baseCurrency) {
                        ForEach(FXStore.supportedCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Toggle("Require \(BiometricAuthenticator.biometryName)", isOn: $lockEnabled)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Locks the app whenever it goes to the background.")
                }

                Section("Your data") {
                    NavigationLink { ManualHoldingsListView() } label: {
                        Label("Outside holdings", systemImage: "building.columns")
                    }
                    NavigationLink { AlertsListView() } label: {
                        Label("Price alerts", systemImage: "bell")
                    }
                }

                Section {
                    LabeledContent("Trading & market data", value: "Alpaca (IEX feed)")
                    LabeledContent("Exchange rates", value: "Frankfurter · ECB")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                } header: {
                    Text("About")
                } footer: {
                    Text("PortfolioLens is a learning project. Paper trading only, and nothing here is investment advice.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { lockEnabled = settings.biometricLockEnabled }
            .onChange(of: settings.dataSource) { environment.reloadDataSource() }
            .onChange(of: lockEnabled) { _, newValue in updateLock(newValue) }
        }
    }

    private var alpacaSection: some View {
        Section {
            if hasSavedKeys {
                Label("Keys saved in the iOS Keychain", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.gain)
            }
            TextField(hasSavedKeys ? "Replace API Key ID" : "API Key ID (starts with PK)", text: $keyID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            SecureField("Secret Key", text: $secretKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

            Button("Save & connect", action: saveKeys)
                .disabled(trimmed(keyID).isEmpty || trimmed(secretKey).isEmpty)

            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    if testState == .testing { ProgressView() }
                }
            }
            .disabled(testState == .testing || (!hasSavedKeys && (trimmed(keyID).isEmpty || trimmed(secretKey).isEmpty)))

            switch testState {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.gain).font(.footnote)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(Theme.loss).font(.footnote)
            default:
                EmptyView()
            }

            if hasSavedKeys {
                Button("Remove keys", role: .destructive, action: removeKeys)
            }
            Link(destination: URL(string: "https://app.alpaca.markets/signup")!) {
                Label("Get free paper-trading keys", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Alpaca paper trading")
        } footer: {
            Text("Free, with no real money involved. Keys are stored only in this device's Keychain. Use **paper** keys from the Alpaca dashboard.")
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveKeys() {
        let credentials = AlpacaCredentials(keyID: trimmed(keyID), secretKey: trimmed(secretKey))
        do {
            try CredentialStore.saveAlpaca(credentials)
            hasSavedKeys = true
            keyID = ""
            secretKey = ""
            testState = .idle
            if settings.dataSource == .alpacaPaper {
                environment.reloadDataSource()
            } else {
                settings.dataSource = .alpacaPaper // onChange reloads the service
            }
        } catch {
            testState = .failure("Couldn't save to the Keychain: \(error.localizedDescription)")
        }
    }

    private func removeKeys() {
        CredentialStore.deleteAlpaca()
        hasSavedKeys = false
        testState = .idle
        settings.dataSource = .demo
    }

    private func testConnection() async {
        testState = .testing
        let typed = AlpacaCredentials(keyID: trimmed(keyID), secretKey: trimmed(secretKey))
        let credentials = typed.keyID.isEmpty || typed.secretKey.isEmpty ? CredentialStore.loadAlpaca() : typed
        guard let credentials else {
            testState = .failure("Enter your keys first.")
            return
        }
        do {
            let account = try await AlpacaBrokerageService(credentials: credentials).fetchAccount()
            testState = .success("Connected to \(account.accountNumber) · equity \(Format.currency(account.equity, code: account.currency))")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func updateLock(_ enabled: Bool) {
        guard enabled != settings.biometricLockEnabled else { return }
        guard enabled else {
            settings.biometricLockEnabled = false
            return
        }
        Task {
            if await BiometricAuthenticator.authenticate(reason: "Turn on app lock") {
                settings.biometricLockEnabled = true
            } else {
                lockEnabled = false
            }
        }
    }
}

struct AlertsListView: View {
    @Environment(AlertCenter.self) private var alertCenter
    @Environment(MarketStore.self) private var store
    @Query(sort: \PriceAlert.createdAt, order: .reverse) private var alerts: [PriceAlert]

    var body: some View {
        let active = alerts.filter(\.isActive)
        let triggered = alerts.filter { !$0.isActive }

        List {
            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { AlertRow(alert: $0) }
                        .onDelete { offsets in
                            for index in offsets { alertCenter.delete(active[index]) }
                        }
                }
            }
            if !triggered.isEmpty {
                Section("Triggered") {
                    ForEach(triggered) { alert in
                        AlertRow(alert: alert)
                            .swipeActions(edge: .leading) {
                                Button("Re-arm") {
                                    alertCenter.reactivate(alert, currentPrice: store.quotes[alert.symbol]?.price)
                                }
                                .tint(Theme.accent)
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets { alertCenter.delete(triggered[index]) }
                    }
                }
            }
        }
        .overlay {
            if alerts.isEmpty {
                ContentUnavailableView("No price alerts", systemImage: "bell.slash",
                                       description: Text("Open any symbol and tap the bell to get notified when it crosses a price."))
            }
        }
        .navigationTitle("Price alerts")
    }
}

struct LockView: View {
    let onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.accent)
                Text("PortfolioLens is locked").font(.title2.bold())
                Button {
                    Task { await unlock() }
                } label: {
                    Label("Unlock with \(BiometricAuthenticator.biometryName)", systemImage: "faceid")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if failed {
                    Text("Authentication failed. Try again.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task { await unlock() }
    }

    private func unlock() async {
        if await BiometricAuthenticator.authenticate(reason: "Unlock your portfolio") {
            onUnlock()
        } else {
            failed = true
        }
    }
}
