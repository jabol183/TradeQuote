import XCTest
@testable import QuoteCore

final class WholeNoteTests: XCTestCase {
    private func lines(_ note: String, _ evidence: [WorkEvidence] = []) -> [QuoteLine] {
        WholeNoteExtraction.resolve(note, evidence: evidence).items.map { SourceExtraction.line(from: $0, source: .note) }
    }
    func testExactScreenshotWithAndWithoutModelSuggestions() throws {
        let example = try XCTUnwrap(ExtractionExample.cases.first { $0.id == "Shared instruction — screenshot" })
        let evidence = [
            WorkEvidence(sourceText: "Two double sockets in the kitchen", objectText: "double sockets", quantityText: "Two", roomText: "kitchen", instructionText: "Replace all parts", supplyText: "provided by customer"),
            WorkEvidence(sourceText: "one light switch in the living room", objectText: "light switch", quantityText: "one", roomText: "living room", instructionText: "Replace all parts", supplyText: "provided by customer")
        ]
        for proposals in [[], evidence] {
            let result = lines(example.note, proposals)
            XCTAssertEqual(result.map(\.title), ["Replace double sockets", "Replace light switch"])
            XCTAssertTrue(ExtractionChecks.problems(result, expected: example.expected).isEmpty)
            XCTAssertTrue(result.allSatisfy { $0.workActionRequired == false && example.note.contains($0.sourceDetail) })
            XCTAssertTrue(result.allSatisfy { $0.sourceDetail.contains("Replace all parts provided by customer") })
        }
    }
    func testModelQuotesCanLinkASeparateQuantityAndSupplySentence() throws {
        let example = ExtractionExample.languageCases[0]
        let evidence = WorkEvidence(sourceText: "Replace the sockets in the kitchen", objectText: "sockets", quantityText: "two", roomText: "kitchen", instructionText: "Replace", supplyText: "customer will provide")
        let result = lines(example.note, [evidence])
        XCTAssertTrue(ExtractionChecks.problems(result, expected: example.expected).isEmpty)
        let item = try XCTUnwrap(result.first)
        XCTAssertTrue(item.sourceDetail.contains("There are two of them"))
        XCTAssertTrue(item.sourceDetail.contains("customer will provide"))
        XCTAssertFalse(item.isReviewed)
        XCTAssertNil(item.approvedUnitPrice)
    }
    func testTwoDistantCountsStayAttachedToDifferentObjectsAndRooms() {
        let example = ExtractionExample.languageCases[1]
        let evidence = [
            WorkEvidence(sourceText: "Replace the kitchen sockets", objectText: "kitchen sockets", quantityText: "two", roomText: "kitchen", instructionText: "Replace", supplyText: "provided by customer"),
            WorkEvidence(sourceText: "Replace the living room switch", objectText: "living room switch", quantityText: "one", roomText: "living room", instructionText: "Replace", supplyText: "provided by customer")
        ]
        XCTAssertTrue(ExtractionChecks.problems(lines(example.note, evidence), expected: example.expected).isEmpty)
    }
    func testAdjacentCountsWithoutPunctuationAreSeparate() {
        let parsed = NoteParser.parse("Two double sockets one light switch")
        XCTAssertEqual(parsed.items.map(\.quantity), [2, 1])
        XCTAssertEqual(parsed.items.map(\.object), ["double sockets", "light switch"])
    }
    func testSharedInstructionDoesNotReplaceAnItemSpecificAction() {
        let parsed = NoteParser.parse("Install two sockets in the kitchen. One switch in the living room. Replace all parts provided by customer.")
        XCTAssertEqual(parsed.items.map(\.action), ["install", "replace"])
        XCTAssertEqual(parsed.items.map(\.supply), [.customer, .customer])
        XCTAssertEqual(parsed.items.map(\.quantity), [2, 1])
    }
    func testSpecificInstructionIsNotTreatedAsGlobal() {
        let parsed = NoteParser.parse("Two lights in the kitchen. Replace all sockets in the bedroom.")
        XCTAssertEqual(parsed.items.count, 2)
        XCTAssertEqual(parsed.items.first?.action, "")
        XCTAssertEqual(parsed.items.last?.action, "replace")
    }
    func testMissingOrConflictingSharedInstructionsStillNeedConfirmation() {
        let parsed = NoteParser.parse("Two sockets. Replace all parts. Install all parts.")
        XCTAssertEqual(parsed.items.count, 1)
        XCTAssertEqual(parsed.items.first?.action, "")
        XCTAssertFalse(parsed.warnings.isEmpty)
        let negation = NoteParser.parse("Two sockets. Do not replace all parts. Replace all parts.")
        XCTAssertEqual(negation.items.first?.action, "")
        XCTAssertFalse(negation.warnings.isEmpty)
        let attemptedOverride = lines("Two sockets. Replace all parts. Install all parts.", [
            WorkEvidence(sourceText: "Two sockets", objectText: "sockets", quantityText: "Two", instructionText: "Replace all parts")])
        XCTAssertEqual(attemptedOverride.first?.workActionRequired, true)
    }
    func testCaptureExampleUnderstandsSeparateSupplyStatement() {
        let parsed = NoteParser.parse("Two sockets in the kitchen, one switch in the living room. Replace all; parts provided by customer.")
        XCTAssertEqual(parsed.items.map(\.quantity), [2, 1])
        XCTAssertEqual(parsed.items.map(\.action), ["replace", "replace"])
        XCTAssertEqual(parsed.items.map(\.supply), [.customer, .customer])
        XCTAssertTrue(parsed.warnings.isEmpty)
    }
    func testUngroundedModelNumbersObjectsAndRoomsAreRejected() {
        let note = "Replace sockets in kitchen. There are two."
        for evidence in [
            WorkEvidence(sourceText: "Replace sockets in kitchen", objectText: "sockets", quantityText: "eight"),
            WorkEvidence(sourceText: "Replace sockets in kitchen", objectText: "switches", quantityText: "two"),
            WorkEvidence(sourceText: "Replace sockets in kitchen", objectText: "sockets", quantityText: "two", roomText: "bedroom")
        ] {
            let result = lines(note, [evidence])
            XCTAssertEqual(result.count, 1)
            XCTAssertNil(result.first?.quantity)
            XCTAssertEqual(result.first?.room, "kitchen")
        }
    }
    func testRatingsCannotSupplyAModelCount() {
        let result = lines("Replace the 13A sockets.", [WorkEvidence(sourceText: "13A sockets", objectText: "sockets", quantityText: "13", instructionText: "Replace")])
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.quantity)
        XCTAssertNil(NoteParser.quantityFact("13A"))
    }
    func testShortenedModelDescriptionsAndCountQuotesCannotDuplicateWorkOrLoseUnits() {
        let items = lines("Install two ceiling light fittings. Allow four hours.", [
            WorkEvidence(sourceText: "two ceiling light fittings", objectText: "light fittings", quantityText: "two", instructionText: "Install"),
            WorkEvidence(sourceText: "four hours", objectText: "hours", quantityText: "four", instructionText: "Allow")])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.quantity), [2, 4])
        XCTAssertEqual(items.map(\.unit), ["each", "h"])
        XCTAssertEqual(items.first?.title, "Install ceiling light fittings")
        let sets = lines("Install two sets of lights.", [WorkEvidence(sourceText: "two sets of lights", objectText: "lights", quantityText: "two", instructionText: "Install")])
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.title, "Install lights")
        XCTAssertEqual(sets.first?.unit, "set")
    }
    func testModelCannotEraseANegationOrLatestCorrection() {
        let negated = lines("Do not replace two sockets.", [WorkEvidence(sourceText: "two sockets", objectText: "sockets", quantityText: "two", instructionText: "replace")])
        XCTAssertEqual(negated.first?.disposition, .excluded)
        let corrected = lines("Replace six sockets. Correction: replace eight sockets, not six.", [WorkEvidence(sourceText: "Replace six sockets", objectText: "sockets", quantityText: "six", instructionText: "Replace")])
        XCTAssertEqual(corrected.count, 1)
        XCTAssertEqual(corrected.first?.quantity, 8)
    }
    func testNoWorkAndOmittedModelItemsCannotCreateOrEraseWork() {
        XCTAssertTrue(lines("The customer has not decided what work they want yet.", [WorkEvidence(sourceText: "what work", objectText: "work")]).isEmpty)
        let result = lines("Replace two sockets. Install one light.", [])
        XCTAssertEqual(result.map(\.quantity), [2, 1])
    }
    func testCatalogueKeepsTheCapturedJobDescription() throws {
        let result = SourceExtraction.prepare("Replace two double sockets.", source: .note, recipes: JobRecipe.starters)
        let line = try XCTUnwrap(result.lines.first)
        XCTAssertNotNil(line.recipeID)
        XCTAssertEqual(line.title, "Replace double sockets")
    }
    func testLaterSharedInstructionUpdatesAnExistingPendingItem() throws {
        let pending = try XCTUnwrap(lines("Two sockets in kitchen").first)
        let completed = lines("Two sockets in kitchen. Replace all parts provided by customer.")
        let changes = WorkflowRules.reconcile(completed, existing: [pending])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.operation, .update)
        XCTAssertEqual(changes.first?.line.id, pending.id)
        XCTAssertEqual(changes.first?.line.workActionRequired, false)
        XCTAssertEqual(changes.first?.line.supply, .customer)
    }
    func testAnActionOnlyChangeIsNotDiscardedAsUnchangedQuantities() throws {
        let pending = try XCTUnwrap(lines("Two sockets in kitchen").first)
        let completed = lines("Two sockets in kitchen. Replace all.")
        let changes = WorkflowRules.reconcile(completed, existing: [pending])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.operation, .update)
        XCTAssertEqual(changes.first?.line.id, pending.id)
        XCTAssertEqual(changes.first?.line.title, "Replace sockets")
        XCTAssertEqual(changes.first?.line.workActionRequired, false)
        XCTAssertEqual(changes.first?.line.quantity, pending.quantity)
    }
    func testFactCheckerRejectsTheWrongActionEvenWhenCountsMatch() {
        let line = QuoteLine(title: "Install sockets", category: .labour, source: .note, quantity: 2)
        XCTAssertFalse(ExtractionChecks.problems([line], expected: [.init("socket", 2, action: "replace")]).isEmpty)
    }
}
