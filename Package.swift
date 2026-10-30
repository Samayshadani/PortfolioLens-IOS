// swift-tools-version:5.9
// Builds only the platform-independent core (Domain + market models) so the business
// logic and its tests run on Windows, Linux or macOS with `swift test`.
// The full iOS app is built from project.yml with Xcode.
import PackageDescription

let package = Package(
    name: "PortfolioLensCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    targets: [
        .target(
            name: "PortfolioLens",
            path: "PortfolioLens",
            exclude: ["App", "DesignSystem", "Features", "Services", "State", "Resources",
                      "Models/PersistentModels.swift"],
            sources: ["Domain", "Models/MarketModels.swift"]
        ),
        .testTarget(
            name: "PortfolioLensCoreTests",
            dependencies: ["PortfolioLens"],
            path: "PortfolioLensTests",
            exclude: ["AlpacaDecodingTests.swift"],
            sources: ["DomainTests.swift"]
        )
    ]
)
