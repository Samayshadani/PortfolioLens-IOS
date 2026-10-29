import SwiftUI
import SwiftData

@main
struct PortfolioLensApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.settings)
                .environment(environment.store)
                .environment(environment.fx)
                .environment(environment.alerts)
        }
        .modelContainer(environment.container)
    }
}
