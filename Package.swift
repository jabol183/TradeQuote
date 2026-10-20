// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TradeQuoteLogic",
    platforms: [.macOS(.v13)],
    products: [.library(name: "QuoteCore", targets: ["QuoteCore"])],
    targets: [
        .target(name: "QuoteCore", path: "TradeQuote.swiftpm/Sources/QuoteCore"),
        .testTarget(name: "QuoteCoreTests", dependencies: ["QuoteCore"], path: "Tests/QuoteCoreTests")
    ]
)
