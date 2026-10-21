import SwiftUI
import QuoteCore

@main
struct TradeQuoteApp: App {
    @State private var store = TradeQuoteStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.blue)
        }
    }
}

enum Theme {
    static let blue = Color(red: 0.14, green: 0.35, blue: 0.96)
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

extension Decimal {
    var editable: String { NSDecimalNumber(decimal: self).stringValue }
}
extension String {
    var asDecimal: Decimal? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: "^-?[0-9]+([.][0-9]*)?$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
extension Date {
    var quoteDate: String { formatted(date: .abbreviated, time: .omitted) }
}

