import Foundation

public enum QuoteEditImpact: Sendable { case scope, pricing, details }

extension QuoteRules {
    /// Shared by app mutations and workflow tests. A check is cleared only when its facts change.
    public static func editDraft(_ quote: inout Quote, impact: QuoteEditImpact, _ change: (inout Quote) -> Void) {
        guard quote.status == .draft else { return }
        let previous = quote
        change(&quote)
        switch impact {
        case .details: break
        case .pricing:
            quote.invalidatePricingApproval()
        case .scope:
            let scopeChanged = previous.lines.map(scopeContent) != quote.lines.map(scopeContent)
            let checksChanged = previous.lines.map(\.isReviewed) != quote.lines.map(\.isReviewed) || previous.materialsConfirmed != quote.materialsConfirmed
            let ratesChanged = previous.lines.map(\.rateID) != quote.lines.map(\.rateID)
            guard scopeChanged || checksChanged || ratesChanged else { return }
            // New or changed AI work needs material review. Explicitly saved/confirmed manual
            // edits already include the item's quantity and material-supply choices.
            if quote.lines.contains(where: { line in
                guard !line.isReviewed else { return false }
                guard let old = previous.lines.first(where: { $0.id == line.id }) else { return true }
                return old.category != line.category || old.supply != line.supply || old.recipeID != line.recipeID
            }) { quote.materialsConfirmed = false }
            quote.invalidatePricingApproval()
            quote.reviewApprovedAt = reviewProblems(quote).isEmpty ? previous.reviewApprovedAt : nil
        }
    }
    private static func scopeContent(_ original: QuoteLine) -> QuoteLine {
        var line = original
        line.isReviewed = false; line.rateID = nil; line.approvedUnitPrice = nil
        return line
    }
}
