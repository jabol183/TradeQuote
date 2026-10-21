import XCTest
@testable import QuoteCore

final class ApprovalWorkflowTests: XCTestCase {
    private var rate: Rate { Rate(name: "Replace socket", category: .labour, unit: "each", amount: 20) }
    private var business: BusinessProfile {
        var profile = BusinessProfile(); profile.name = "Contractor"; profile.address = "Address"; profile.vatPercent = 20
        return profile
    }
    private func draft(_ rate: Rate) -> Quote {
        var line = QuoteLine(title: "Replace socket", category: .labour, source: .voice, quantity: 2,
            confirmationPrompt: "Confirm type and finish.", isReviewed: true, rateID: rate.id)
        line.supply = .customer; line.confirmationKind = .specification
        var quote = Quote(number: "APPROVAL", lines: [line], materialsConfirmed: true)
        quote.billingMethod = .perTask; quote.workflowVersion = 2
        return quote
    }
    private func approved(_ rate: Rate) -> Quote {
        var quote = draft(rate)
        XCTAssertTrue(QuoteRules.approveScopeAndPricing(&quote, rates: [rate], business: business))
        return quote
    }
    func testOptionalSpecificationTextDoesNotControlApproval() {
        let rate = rate
        for text in ["", ".", "White double socket"] {
            var quote = draft(rate); quote.lines[0].specification = text
            XCTAssertTrue(WorkflowRules.canConfirm(quote.lines[0]))
            XCTAssertTrue(QuoteRules.approveScopeAndPricing(&quote, rates: [rate], business: business))
        }
    }
    func testMeaningfulMissingFactsStillBlockConfirmation() {
        var line = draft(rate).lines[0]
        line.quantity = nil
        XCTAssertFalse(WorkflowRules.canConfirm(line))
        line.quantity = 2; line.workActionRequired = true
        XCTAssertFalse(WorkflowRules.canConfirm(line))
        line.workActionRequired = false; line.unit = " "
        XCTAssertFalse(WorkflowRules.canConfirm(line))
    }
    func testBillingMethodAndFixedPriceKeepPreviousScopeChecks() {
        let rate = rate; var quote = approved(rate); let scopeDate = quote.reviewApprovedAt
        QuoteRules.editDraft(&quote, impact: .pricing) { $0.billingMethod = .fixed; $0.fixedLabourPrice = 150 }
        XCTAssertEqual(quote.reviewApprovedAt, scopeDate)
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(quote.lines[0].isReviewed)
        XCTAssertNil(quote.pricingApprovedAt)
        XCTAssertNil(quote.approvedVATPercent)
        XCTAssertNil(quote.lines[0].approvedUnitPrice)
        XCTAssertTrue(QuoteRules.approvePricing(&quote, rates: [], business: business))
        XCTAssertEqual(QuoteRules.totals(quote, rates: [], vatPercent: 20)?.total, 180)
    }
    func testChangingARateNeedsOnlyPricingApproval() {
        let original = rate; var quote = approved(original); let scopeDate = quote.reviewApprovedAt
        let replacement = Rate(name: "Another rate", category: .labour, unit: "each", amount: 30)
        QuoteRules.editDraft(&quote, impact: .pricing) { $0.lines[0].rateID = replacement.id }
        XCTAssertEqual(quote.reviewApprovedAt, scopeDate)
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(quote.lines[0].isReviewed)
        XCTAssertTrue(QuoteRules.approvePricing(&quote, rates: [replacement], business: business))
        XCTAssertEqual(QuoteRules.totals(quote, rates: [], vatPercent: 20)?.total, 72)
    }
    func testConfirmedManualQuantityEditDoesNotRequireScopeReviewAgain() {
        let rate = rate; var quote = approved(rate); let scopeDate = quote.reviewApprovedAt
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].quantity = 3; $0.lines[0].isReviewed = true }
        XCTAssertEqual(quote.reviewApprovedAt, scopeDate)
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(quote.lines[0].isReviewed)
        XCTAssertNil(quote.pricingApprovedAt)
        XCTAssertTrue(QuoteRules.approvePricing(&quote, rates: [rate], business: business))
        XCTAssertEqual(QuoteRules.totals(quote, rates: [], vatPercent: 20)?.total, 72)
    }
    func testPendingChangeCanBeConfirmedAndPricedInTheCurrentStep() {
        let rate = rate; var quote = approved(rate)
        var other = quote.lines[0]; other.id = UUID(); other.title = "Second socket"
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines.append(other) }
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].quantity = 3; $0.lines[0].isReviewed = false }
        XCTAssertNil(quote.reviewApprovedAt)
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(quote.lines[1].isReviewed)
        XCTAssertFalse(QuoteRules.approveScopeAndPricing(&quote, rates: [rate], business: business))
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].isReviewed = true }
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(QuoteRules.pricingProblems(quote, rates: [rate], business: business, requiresScopeApproval: false).isEmpty)
        XCTAssertTrue(QuoteRules.approveScopeAndPricing(&quote, rates: [rate], business: business))
        XCTAssertNotNil(quote.reviewApprovedAt)
        XCTAssertNotNil(quote.pricingApprovedAt)
    }
    func testNewUnreviewedWorkDoesNotEraseOtherItemChecks() {
        let rate = rate; var quote = approved(rate)
        var added = QuoteLine(title: "Install socket", category: .labour, source: .voice, quantity: 1, rateID: rate.id)
        added.supply = .contractor
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines.append(added) }
        XCTAssertTrue(quote.lines[0].isReviewed)
        XCTAssertFalse(quote.lines[1].isReviewed)
        XCTAssertFalse(quote.materialsConfirmed)
        XCTAssertNil(quote.reviewApprovedAt)
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[1].isReviewed = true; $0.materialsConfirmed = true }
        XCTAssertTrue(QuoteRules.approveScopeAndPricing(&quote, rates: [rate], business: business))
    }
    func testAddingConfirmedHoursWhilePricingKeepsPreviousChecks() {
        let rate = rate; var quote = approved(rate)
        QuoteRules.editDraft(&quote, impact: .pricing) { $0.billingMethod = .hourly }
        let hourly = Rate(name: "Hours", category: .labour, unit: "h", amount: 50)
        var hours = QuoteLine(title: "Whole-job labour", category: .labour, source: .manual, quantity: 4, unit: "h", isReviewed: true, rateID: hourly.id)
        hours.supply = MaterialSupply.none
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines.append(hours) }
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertNotNil(quote.reviewApprovedAt)
        XCTAssertTrue(quote.lines.allSatisfy(\.isReviewed))
        XCTAssertTrue(QuoteRules.approvePricing(&quote, rates: [hourly], business: business))
        XCTAssertEqual(QuoteRules.totals(quote, rates: [], vatPercent: 20)?.total, 240)
    }
    func testFailedCombinedApprovalIsAtomic() {
        let rate = rate; var quote = draft(rate)
        XCTAssertNil(quote.reviewApprovedAt)
        XCTAssertFalse(QuoteRules.approveScopeAndPricing(&quote, rates: [], business: business))
        XCTAssertNil(quote.reviewApprovedAt)
        XCTAssertNil(quote.pricingApprovedAt)
        XCTAssertNil(quote.lines[0].approvedUnitPrice)
        XCTAssertTrue(quote.materialsConfirmed)
    }
    func testConfirmingAnItemDoesNotClearTheMaterialsCheck() {
        let rate = rate; var quote = draft(rate); quote.lines[0].isReviewed = false
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].isReviewed = true }
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(QuoteRules.reviewProblems(quote).isEmpty)
    }
    func testUnchangedScopeAndExtraEvidenceDoNotClearApproval() {
        let rate = rate; var quote = approved(rate); let scope = quote.reviewApprovedAt, pricing = quote.pricingApprovedAt
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].quantity = 2 }
        QuoteRules.editDraft(&quote, impact: .scope) { $0.notes += "Extra source context"; $0.photoNames.append("photo.jpg") }
        XCTAssertEqual(quote.reviewApprovedAt, scope)
        XCTAssertEqual(quote.pricingApprovedAt, pricing)
        XCTAssertTrue(quote.materialsConfirmed)
    }
    func testSavingAnUnchangedConfirmedItemKeepsFrozenPrices() {
        let rate = self.rate; var quote = approved(rate)
        let savedLine = quote.lines[0], pricing = quote.pricingApprovedAt
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0] = savedLine }
        XCTAssertEqual(quote.pricingApprovedAt, pricing)
        XCTAssertEqual(quote.lines[0].approvedUnitPrice, 20)
        XCTAssertTrue(quote.materialsConfirmed)
        XCTAssertTrue(quote.lines[0].isReviewed)
    }
    func testInvalidEditsStillBlockFinalizationButCanBeFixedLocally() {
        let rate = rate; var quote = approved(rate)
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].quantity = nil; $0.lines[0].isReviewed = false }
        let issues = QuoteRules.finalizationProblems(quote, rates: [rate], business: business, customers: [])
        XCTAssertTrue(issues.contains(.unconfirmedItem))
        XCTAssertTrue(issues.contains(.pricingNotApproved))
        QuoteRules.editDraft(&quote, impact: .scope) { $0.lines[0].quantity = 2; $0.lines[0].isReviewed = true }
        XCTAssertTrue(QuoteRules.approveScopeAndPricing(&quote, rates: [rate], business: business))
    }
    func testFinalDocumentsAreNotEditedThroughDraftOperations() {
        let rate = rate; var quote = approved(rate); quote.status = .final
        let approvedPrice = quote.lines[0].approvedUnitPrice
        QuoteRules.editDraft(&quote, impact: .pricing) { $0.lines[0].quantity = 100 }
        XCTAssertEqual(quote.status, .final)
        XCTAssertEqual(quote.lines[0].quantity, 2)
        XCTAssertEqual(quote.lines[0].approvedUnitPrice, approvedPrice)
    }
}
