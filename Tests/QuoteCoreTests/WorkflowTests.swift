import XCTest
@testable import QuoteCore

final class WorkflowTests: XCTestCase {
    private func reviewed(_ title: String, category: LineCategory = .labour, quantity: Decimal = 1, unit: String = "each", rate: Rate? = nil) -> QuoteLine {
        QuoteLine(title: title, category: category, source: .manual, quantity: quantity, unit: unit, isReviewed: true, rateID: rate?.id)
    }
    func testHourlyBillingDoesNotChargeTaskLabourTwice() {
        let task = Rate(name: "Socket labour", category: .labour, unit: "each", amount: 20)
        let hourly = Rate(name: "Hourly labour", category: .labour, unit: "h", amount: 50)
        var q = Quote(number: "1", lines: [reviewed("Sockets", quantity: 6, rate: task), reviewed("Whole job", quantity: 4, unit: "h", rate: hourly)], materialsConfirmed: true)
        q.billingMethod = .hourly; q.reviewApprovedAt = Date()
        var b = BusinessProfile(); b.vatPercent = 20
        XCTAssertTrue(QuoteRules.approvePricing(&q, rates: [task, hourly], business: b))
        XCTAssertEqual(QuoteRules.totals(q, rates: [], vatPercent: 20)?.total, 240)
        XCTAssertEqual(q.lines[0].approvedUnitPrice, 0)
    }
    func testPerTaskPricingKeepsHoursAsInternalAllowance() {
        let rate = Rate(name: "Socket labour", category: .labour, unit: "each", amount: 20)
        var q = Quote(number: "2", lines: [reviewed("Sockets", quantity: 6, rate: rate), reviewed("Allowance", quantity: 4, unit: "h")], materialsConfirmed: true)
        q.billingMethod = .perTask
        XCTAssertEqual(QuoteRules.totals(q, rates: [rate], vatPercent: 0)?.total, 120)
    }
    func testFixedPriceAndCustomerMaterials() {
        var material = reviewed("Fittings", category: .materials, quantity: 2); material.supply = .customer
        var q = Quote(number: "3", lines: [reviewed("Install lights", quantity: 2), material], materialsConfirmed: true)
        q.billingMethod = .fixed; q.fixedLabourPrice = 180; q.reviewApprovedAt = Date()
        var b = BusinessProfile(); b.vatPercent = 0
        XCTAssertTrue(QuoteRules.approvePricing(&q, rates: [], business: b))
        XCTAssertEqual(QuoteRules.totals(q, rates: [], vatPercent: 0)?.total, 180)
    }
    func testOptionalAndExcludedItemsDoNotIncreaseTotal() {
        let rate = Rate(name: "Task", category: .labour, unit: "each", amount: 10)
        let first = reviewed("Included", rate: rate)
        var optional = reviewed("Optional", rate: rate); optional.disposition = .optional
        var excluded = reviewed("Excluded", rate: rate); excluded.disposition = .excluded
        var q = Quote(number: "4", lines: [first, optional, excluded])
        XCTAssertEqual(QuoteRules.totals(q, rates: [rate], vatPercent: 0)?.total, 10)
        q.lines[1].optionalSelected = true
        XCTAssertEqual(QuoteRules.totals(q, rates: [rate], vatPercent: 0)?.total, 20)
    }
    func testLegacyOverlappingLabourBlocksApproval() {
        var q = Quote(number: "5", lines: [reviewed("Sockets"), reviewed("Hours", unit: "h")], materialsConfirmed: true)
        q.reviewApprovedAt = Date()
        XCTAssertTrue(QuoteRules.pricingProblems(q, rates: [], business: BusinessProfile()).contains(.billingOverlap))
    }
    func testRecipeSupplyAndSpecificationNeedAnswers() {
        let recipe = JobRecipe.starters[0]
        var line = recipe.scopeLine(quantity: 6)
        XCTAssertFalse(WorkflowRules.canConfirm(line))
        line.specification = "Double white sockets"; line.supply = .contractor
        XCTAssertTrue(WorkflowRules.canConfirm(line))
        line.confirmationKind = .quantity; line.specification = ""; line.confirmationPrompt = "How many?"
        XCTAssertTrue(WorkflowRules.canConfirm(line))
    }
    func testRecipeContainerNeverChargesAlongsideComponents() {
        var line = reviewed("Recipe parent"); line.isRecipeContainer = true
        let q = Quote(number: "6", lines: [line])
        XCTAssertFalse(WorkflowRules.isChargeable(line, in: q))
    }
    func testReanalysisUpdatesStableItemInsteadOfAppending() {
        let recipe = JobRecipe.starters[0]
        var old = recipe.scopeLine(quantity: 6); old.room = "Kitchen"
        var new = recipe.scopeLine(quantity: 8); new.room = "kitchen"
        let changes = WorkflowRules.reconcile([new], existing: [old])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.operation, .update)
        XCTAssertEqual(changes.first?.line.id, old.id)
        XCTAssertEqual(changes.first?.line.quantity, 8)
        XCTAssertTrue(WorkflowRules.reconcile([old], existing: [old]).isEmpty)
    }
    func testSimilarWorkInDifferentRoomsIsSeparate() {
        let recipe = JobRecipe.starters[0]
        var a = recipe.scopeLine(quantity: 2); a.room = "Kitchen"
        var b = recipe.scopeLine(quantity: 3); b.room = "Bedroom"
        XCTAssertEqual(WorkflowRules.reconcile([b], existing: [a]).first?.operation, .add)
        XCTAssertEqual(WorkflowRules.reconcile([a, a], existing: []).last?.operation, .conflict)
    }
    func testRecipeMatchingDistinguishesReplacingFromNewPoints() {
        XCTAssertEqual(WorkflowRules.searchRecipes("replace six sockets", recipes: JobRecipe.starters).first?.name, "Replace existing socket")
        XCTAssertEqual(WorkflowRules.searchRecipes("install new socket", recipes: JobRecipe.starters).first?.name, "Install new socket point")
    }
    func testEvidenceNumbersMustBePresentWithoutSubstringMatches() {
        XCTAssertTrue(EvidenceRules.supports(6, in: "Replace six sockets"))
        XCTAssertTrue(EvidenceRules.supports(Decimal(string: "1.5")!, in: "allow 1.5 hours"))
        XCTAssertFalse(EvidenceRules.supports(6, in: "Replace 16 sockets"))
        XCTAssertFalse(EvidenceRules.supports(6, in: "Replace sockets"))
    }
    func testQuotedCSVAndImportValidation() throws {
        let csv = "name,category,unit,amount,aliases,purchasecost\n\"Socket, white\",Materials,each,5.50,socket|faceplate,3.20\n"
        let rates = try RateCSV.parse(csv)
        XCTAssertEqual(rates.count, 1); XCTAssertEqual(rates[0].name, "Socket, white")
        XCTAssertEqual(rates[0].amount, Decimal(string: "5.50"))
        XCTAssertThrowsError(try RateCSV.parse("name,category,unit,amount\nTask,Labour,h,-10"))
        XCTAssertThrowsError(try RateCSV.parse("name,category,unit,amount\n\"Unclosed,Labour,h,10"))
    }
    func testV1SnapshotDecodesWithNewOptionalFieldsAbsent() throws {
        let data = Data("{\"quotes\":[],\"customers\":[],\"rates\":[],\"business\":{\"name\":\"\",\"email\":\"\",\"address\":\"\",\"telephone\":\"\",\"taxIdentifier\":\"\",\"currencyCode\":\"GBP\",\"terms\":\"\"}}".utf8)
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: data)
        XCTAssertNil(snapshot.recipes)
        let q = Quote(number: "legacy")
        let decoded = try JSONDecoder().decode(Quote.self, from: JSONEncoder().encode(q))
        XCTAssertNil(decoded.billingMethod)
    }
    func testBackupRejectsPathTraversalAndMissingFinalPDF() {
        let bad = BackupArchive(snapshot: AppSnapshot(), photos: ["../evil.jpg": Data()], pdfs: [:])
        XCTAssertThrowsError(try bad.validate())
        var snapshot = AppSnapshot(); var q = Quote(number: "final"); q.finalizedAt = Date(); snapshot.quotes = [q]
        XCTAssertThrowsError(try BackupArchive(snapshot: snapshot, photos: [:], pdfs: [:]).validate())
    }
    func testBackupRoundTripPreservesRecipesAndSources() throws {
        var snapshot = AppSnapshot(); snapshot.recipes = JobRecipe.starters
        var q = Quote(number: "roundtrip"); q.lines = [snapshot.recipes![0].scopeLine(quantity: 2)]; snapshot.quotes = [q]
        let archive = BackupArchive(snapshot: snapshot, photos: [:], pdfs: [:])
        let restored = try JSONDecoder().decode(BackupArchive.self, from: JSONEncoder().encode(archive))
        try restored.validate()
        XCTAssertEqual(restored.snapshot.recipes?.count, 16)
        XCTAssertEqual(restored.snapshot.quotes[0].lines[0].recipeID, q.lines[0].recipeID)
    }
}
