import Foundation

public struct PriceBreakdown: Equatable, Sendable {
    public var subtotal: Decimal
    public var vat: Decimal
    public var total: Decimal
    public init(subtotal: Decimal, vat: Decimal, total: Decimal) {
        self.subtotal = subtotal
        self.vat = vat
        self.total = total
    }
}

public enum QuoteRules {
    public static func roundMoney(_ amount: Decimal) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    public static func reviewProblems(_ quote: Quote) -> [QuoteProblem] {
        if quote.lines.isEmpty { return [.noLines] }
        var issues: [QuoteProblem] = []
        let incomplete = quote.lines.contains { line in
            line.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !line.isReviewed || line.quantity == nil || (line.quantity ?? 0) <= 0 ||
            line.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if incomplete { issues.append(.unconfirmedItem) }
        if !quote.materialsConfirmed { issues.append(.materialsNotReviewed) }
        if quote.lines.contains(where: {
            $0.confirmationPrompt != nil && $0.specification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) { issues.append(.missingSpecification) }
        return issues
    }

    /// Canonical form of a unit so "Hours", "hrs" and "h" all match the same saved rate.
    public static func normalizedUnit(_ unit: String) -> String {
        let key = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch key {
        case "h", "hr", "hrs", "hour", "hours": return "h"
        case "each", "ea", "pc", "pcs", "piece", "pieces", "item", "items", "unit", "units", "no", "x": return "each"
        case "day", "days", "d": return "day"
        case "m", "metre", "metres", "meter", "meters", "lm": return "m"
        case "m2", "m²", "sqm", "sq m", "square metre", "square metres", "square meter", "square meters": return "m²"
        case "set", "sets": return "set"
        default: return key
        }
    }

    /// True for filler the model writes instead of leaving a field empty ("None", "N/A", "-", ...).
    public static func isPlaceholder(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        return ["", "none", "n/a", "na", "null", "nil", "nothing", "unknown", "not specified",
                "unspecified", "not applicable", "no", "empty"].contains(key)
    }

    /// Clears placeholder confirmation questions and units left by earlier AI drafts.
    public static func cleanedAIPlaceholders(_ line: QuoteLine) -> QuoteLine {
        var line = line
        if let prompt = line.confirmationPrompt, isPlaceholder(prompt) { line.confirmationPrompt = nil }
        if isPlaceholder(line.unit) { line.unit = "each" }
        if isPlaceholder(line.specification) { line.specification = "" }
        return line
    }

    public static func unitsMatch(_ a: String, _ b: String) -> Bool {
        normalizedUnit(a) == normalizedUnit(b)
    }

    public static func rate(for line: QuoteLine, in rates: [Rate]) -> Rate? {
        rates.first(where: { $0.id == line.rateID && $0.category == line.category && unitsMatch($0.unit, line.unit) })
    }

    public static func pricingProblems(_ quote: Quote, rates: [Rate], business: BusinessProfile) -> [QuoteProblem] {
        var issues = reviewProblems(quote)
        if quote.reviewApprovedAt == nil { issues.append(.reviewNotApproved) }
        let vat = quote.pricingApprovedAt != nil ? quote.approvedVATPercent : business.vatPercent
        if vat == nil || (vat ?? 0) < 0 || (vat ?? 0) > 100 { issues.append(.missingVAT) }
        if quote.lines.contains(where: { line in
            if quote.pricingApprovedAt != nil {
                guard let price = line.approvedUnitPrice else { return true }
                return price < 0
            }
            guard let rate = rate(for: line, in: rates), let price = rate.amount else { return true }
            return price < 0
        }) { issues.append(.missingRate) }
        return issues
    }

    /// Does not guess missing rates. Returns nil while any line lacks a valid saved rate.
    public static func totals(_ quote: Quote, rates: [Rate], vatPercent: Decimal) -> PriceBreakdown? {
        guard vatPercent >= 0, vatPercent <= 100, !quote.lines.isEmpty else { return nil }
        var subtotal: Decimal = 0
        for line in quote.lines {
            guard let quantity = line.quantity, quantity > 0 else { return nil }
            let rateAmount: Decimal?
            if quote.pricingApprovedAt != nil {
                rateAmount = line.approvedUnitPrice
            } else {
                rateAmount = rate(for: line, in: rates)?.amount
            }
            guard let price = rateAmount, price >= 0 else { return nil }
            subtotal += roundMoney(quantity * price)
        }
        let vat = roundMoney(subtotal * vatPercent / 100)
        return PriceBreakdown(subtotal: roundMoney(subtotal), vat: vat, total: roundMoney(subtotal + vat))
    }

    public static func approvePricing(_ quote: inout Quote, rates: [Rate], business: BusinessProfile, at date: Date = Date()) -> Bool {
        guard pricingProblems(quote, rates: rates, business: business).isEmpty,
              let vat = business.vatPercent else { return false }
        for i in quote.lines.indices {
            guard let price = rate(for: quote.lines[i], in: rates)?.amount else { return false }
            quote.lines[i].approvedUnitPrice = price
        }
        quote.approvedVATPercent = vat
        quote.approvedCurrencyCode = business.currencyCode
        quote.pricingApprovedAt = date
        return true
    }

    public static func finalizationProblems(_ quote: Quote, rates: [Rate], business: BusinessProfile, customers: [Customer]) -> [QuoteProblem] {
        var issues = reviewProblems(quote)
        if quote.reviewApprovedAt == nil { issues.append(.reviewNotApproved) }
        if quote.pricingApprovedAt == nil || quote.approvedVATPercent == nil { issues.append(.pricingNotApproved) }
        if business.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           business.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingBusiness)
        }
        if !customers.contains(where: { $0.id == quote.customerID && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(.missingCustomer)
        }
        if quote.approvedVATPercent == nil { issues.append(.missingVAT) }
        if quote.pricingApprovedAt != nil {
            if quote.lines.contains(where: { $0.approvedUnitPrice == nil }) { issues.append(.missingRate) }
        } else if quote.lines.contains(where: { rate(for: $0, in: rates)?.amount == nil }) {
            issues.append(.missingRate)
        }
        return issues
    }
}
