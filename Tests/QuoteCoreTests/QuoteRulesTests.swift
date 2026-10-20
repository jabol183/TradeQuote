import XCTest
@testable import QuoteCore

final class QuoteRulesTests: XCTestCase {
    func testAbsentRatesAlwaysBlockPricing() {
        let line = QuoteLine(title: "Replace socket", category: .labour, source: .voice, quantity: 6, isReviewed: true)
        var quote = Quote(number: "QT-1", lines: [line], materialsConfirmed: true)
        quote.reviewApprovedAt = Date()
        var business = BusinessProfile()
        business.vatPercent = 20
        XCTAssertTrue(QuoteRules.pricingProblems(quote, rates: [], business: business).contains(.missingRate))
        XCTAssertNil(QuoteRules.totals(quote, rates: [], vatPercent: 20))
        XCTAssertFalse(QuoteRules.approvePricing(&quote, rates: [], business: business))
    }

    func testUnspecifiedAIItemCannotBeApproved() {
        let line = QuoteLine(title: "Install light fitting", category: .labour, source: .photo,
                             quantity: 2, confirmationPrompt: "Which fitting?", isReviewed: true)
        let quote = Quote(number: "QT-2", lines: [line])
        XCTAssertTrue(QuoteRules.reviewProblems(quote).contains(.missingSpecification))
    }

    func testDeterministicAmountsAndFrozenRates() {
        let rate = Rate(name: "Electrical labour", category: .labour, unit: "h", amount: Decimal(string:"50.00")!)
        let line = QuoteLine(title: "Electrical labour", category: .labour, source: .voice,
                             quantity: 4, unit:"h", isReviewed: true, rateID:rate.id)
        var quote = Quote(number:"QT-3", lines:[line], materialsConfirmed: true)
        quote.reviewApprovedAt = Date()
        var business = BusinessProfile()
        business.vatPercent = 20
        XCTAssertTrue(QuoteRules.approvePricing(&quote, rates:[rate], business:business))
        let changedRate = Rate(id:rate.id, name:rate.name, category:rate.category, unit:"h", amount:100)
        let amounts = QuoteRules.totals(quote, rates:[changedRate], vatPercent: quote.approvedVATPercent!)!
        XCTAssertEqual(amounts.subtotal, 200)
        XCTAssertEqual(amounts.vat, 40)
        XCTAssertEqual(amounts.total, 240)
    }

    func testLineEditsInvalidateApproval() {
        var quote = Quote(number:"QT-4", lines:[QuoteLine(title:"Task", category:.labour, source:.manual, quantity:1)])
        quote.reviewApprovedAt = Date()
        quote.pricingApprovedAt = Date()
        quote.lines[0].approvedUnitPrice = 9
        quote.invalidateApprovals()
        XCTAssertNil(quote.reviewApprovedAt)
        XCTAssertNil(quote.pricingApprovedAt)
        XCTAssertNil(quote.lines[0].approvedUnitPrice)
    }

    func testMaterialReviewIsRequiredEvenForLabourOnlyQuotes() {
        var quote = Quote(number: "QT-5", lines: [
            QuoteLine(title: "Inspection", category: .labour, source: .manual, quantity: 1, isReviewed: true)
        ])
        XCTAssertTrue(QuoteRules.reviewProblems(quote).contains(.materialsNotReviewed))
        quote.materialsConfirmed = true
        XCTAssertFalse(QuoteRules.reviewProblems(quote).contains(.materialsNotReviewed))
    }

    func testRounding() {
        XCTAssertEqual(QuoteRules.roundMoney(Decimal(string:"1.005")!), Decimal(string:"1.01")!)
        XCTAssertEqual(QuoteRules.roundMoney(Decimal(string:"0.994")!), Decimal(string:"0.99")!)
    }

    func testUnitSynonymsMatchSavedRate() {
        let rate = Rate(name: "Labour", category: .labour, unit: "h", amount: 40)
        let line = QuoteLine(title: "Labour", category: .labour, source: .voice,
                             quantity: 3, unit: "Hours", isReviewed: true, rateID: rate.id)
        XCTAssertEqual(QuoteRules.rate(for: line, in: [rate])?.id, rate.id)
        XCTAssertTrue(QuoteRules.unitsMatch("pcs", "each"))
        XCTAssertFalse(QuoteRules.unitsMatch("h", "each"))
    }

    func testAIPlaceholdersAreCleared() {
        let line = QuoteLine(title: "Double socket", category: .materials, source: .voice,
                             unit: "none", specification: "None", confirmationPrompt: "None.")
        let cleaned = QuoteRules.cleanedAIPlaceholders(line)
        XCTAssertNil(cleaned.confirmationPrompt)
        XCTAssertEqual(cleaned.unit, "each")
        XCTAssertEqual(cleaned.specification, "")
        let real = QuoteLine(title: "Light", category: .materials, source: .voice, confirmationPrompt: "Which fitting?")
        XCTAssertEqual(QuoteRules.cleanedAIPlaceholders(real).confirmationPrompt, "Which fitting?")
    }

    func testRateWithDifferentCategoryIsNotUsed() {
        let rate = Rate(name: "Socket", category: .materials, unit: "each", amount: 5)
        let line = QuoteLine(title: "Socket", category: .labour, source: .manual,
                             quantity: 1, isReviewed: true, rateID: rate.id)
        XCTAssertNil(QuoteRules.rate(for: line, in: [rate]))
    }
}
