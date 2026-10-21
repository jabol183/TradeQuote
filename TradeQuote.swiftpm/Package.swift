// swift-tools-version: 6.0
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "TradeQuote",
    platforms: [.iOS("26.0")],
    products: [
        .iOSApplication(
            name: "TradeQuote",
            targets: ["AppModule"],
            bundleIdentifier: "com.tradequote.ai",
            displayVersion: "1.1.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .lightningBolt),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [.portrait, .landscapeRight, .landscapeLeft],
            additionalInfoPlistContentFilePath: "Supporting/Info.plist"
        )
    ],
    targets: [
        .target(name: "QuoteCore", path: "Sources/QuoteCore"),
        .executableTarget(name: "AppModule", dependencies: ["QuoteCore"], path: "Sources/AppModule")
    ],
    swiftLanguageVersions: [.version("6")]
)

