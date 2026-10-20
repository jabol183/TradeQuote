import AppIntents
import Foundation

extension Notification.Name {
    static let startNewTradeQuote = Notification.Name("TradeQuote.StartNewQuote")
}

/// Siri/Shortcuts opens capture, never invents work, sets a rate, or sends a quote.
struct StartTradeQuoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Trade Quote"
    static let description = IntentDescription("Opens TradeQuote to photograph and dictate a new quotation.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "TradeQuote.PendingNewQuote")
        NotificationCenter.default.post(name: .startNewTradeQuote, object: nil)
        return .result()
    }
}

struct TradeQuoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTradeQuoteIntent(),
            phrases: [
                "Start a quote in \(.applicationName)",
                "New quotation in \(.applicationName)"
            ],
            shortTitle: "New Trade Quote",
            systemImageName: "doc.badge.plus"
        )
    }
}
