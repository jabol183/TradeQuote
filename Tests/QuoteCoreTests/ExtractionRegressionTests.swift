import XCTest
@testable import QuoteCore

final class ExtractionRegressionTests: XCTestCase {
    func testQuantityListsKeepFactsAndRequireAManualAction() {
        for separator in ["\n", "; ", ", ", " and "] {
            let note = "2 double sockets in living room" + separator + "two light switches in the kitchen"
            let result = SourceExtraction.prepare(note, source: .voice, recipes: JobRecipe.starters)
            XCTAssertTrue(result.warnings.isEmpty, note)
            XCTAssertEqual(result.lines.count, 2, note)
            XCTAssertEqual(result.lines.map(\.quantity), [2, 2])
            XCTAssertEqual(result.lines.map(\.room), ["living room", "kitchen"])
            XCTAssertEqual(result.lines.map(\.title), ["Double sockets", "Light switches"])
            for line in result.lines {
                XCTAssertEqual(line.workActionRequired, true)
                XCTAssertEqual(line.supply, .unknown)
                XCTAssertNil(line.recipeID, "A recipe must not choose install versus replace")
                XCTAssertFalse(WorkflowRules.canConfirm(line))
                XCTAssertTrue(note.contains(line.sourceDetail))
            }
        }
    }
    func testActionChoicePreservesCapturedFactsAndResetsApproval() throws {
        let note = "2 double sockets in living room"
        var line = try XCTUnwrap(SourceExtraction.prepare(note, source: .voice, recipes: JobRecipe.starters).lines.first)
        line.isReviewed = true; line.rateID = UUID(); line.approvedUnitPrice = 99
        let resolved = WorkflowRules.choosingAction(.replace, for: line)
        XCTAssertEqual(resolved.title, "Replace double sockets")
        XCTAssertEqual(resolved.quantity, 2)
        XCTAssertEqual(resolved.room, "living room")
        XCTAssertEqual(resolved.sourceDetail, note)
        XCTAssertEqual(resolved.sourceStart, line.sourceStart)
        XCTAssertEqual(resolved.sourceLength, line.sourceLength)
        XCTAssertEqual(resolved.supply, .unknown)
        XCTAssertEqual(resolved.workActionRequired, false)
        XCTAssertNil(resolved.confirmationPrompt)
        XCTAssertFalse(resolved.isReviewed)
        XCTAssertNil(resolved.rateID)
        XCTAssertNil(resolved.approvedUnitPrice)
        XCTAssertTrue(WorkflowRules.canConfirm(resolved))
    }
    func testSpecificationOrReviewedFlagCannotBypassMissingAction() throws {
        var line = try XCTUnwrap(SourceExtraction.prepare("2 sockets in kitchen", source: .note, recipes: []).lines.first)
        line.specification = "White double sockets"; line.isReviewed = true
        XCTAssertFalse(WorkflowRules.canConfirm(line))
        var quote = Quote(number: "TEST"); quote.lines = [line]; quote.materialsConfirmed = true
        XCTAssertTrue(QuoteRules.reviewProblems(quote).contains(.unconfirmedItem))
    }
    func testExplicitSupplyChoiceIsAMaterialPurchase() throws {
        let line = try XCTUnwrap(SourceExtraction.prepare("2 sockets", source: .note, recipes: []).lines.first)
        let resolved = WorkflowRules.choosingAction(.supply, for: line)
        XCTAssertEqual(resolved.category, .materials)
        XCTAssertEqual(resolved.supply, .contractor)
        XCTAssertEqual(resolved.title, "Supply sockets")
    }
    func testNewListEntryDoesNotInheritActionAcrossASentenceOrNewline() {
        for separator in [". ", "\n", "; "] {
            let parsed = NoteParser.parse("Replace 2 sockets" + separator + "3 light switches")
            XCTAssertEqual(parsed.items.map(\.action), ["replace", ""])
        }
        XCTAssertEqual(NoteParser.parse("Replace 2 sockets and 3 light switches").items.map(\.action), ["replace", "replace"])
        XCTAssertEqual(NoteParser.parse("2 sockets\n3").items.count, 1)
    }
    func testMissingActionStateSurvivesStorageAndOldLinesRemainCompatible() throws {
        let line = try XCTUnwrap(SourceExtraction.prepare("2 sockets", source: .note, recipes: []).lines.first)
        let encoded = try JSONEncoder().encode(line)
        let restored = try JSONDecoder().decode(QuoteLine.self, from: encoded)
        XCTAssertEqual(restored.workActionRequired, true)
        XCTAssertEqual(restored.capturedWorkObject, "sockets")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "workActionRequired"); old.removeValue(forKey: "capturedWorkObject")
        let legacy = try JSONDecoder().decode(QuoteLine.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.workActionRequired)
    }
    func testEveryDeviceScreenshotScenarioThroughProductionFactPreparation() {
        for example in ExtractionExample.cases {
            let result = SourceExtraction.prepare(example.note, source: .voice, recipes: JobRecipe.starters)
            let failures = ExtractionChecks.problems(result.lines, expected: example.expected)
            XCTAssertTrue(failures.isEmpty, "\(example.id): \(failures.joined(separator: " "))\n" + result.lines.map { "\($0.title) \(String(describing: $0.quantity)) \($0.unit) \($0.room ?? "")" }.joined(separator: "\n"))
            for line in result.lines { XCTAssertTrue(example.note.contains(line.sourceDetail), "Evidence must be a literal source span") }
        }
    }
    func testCheckerCannotPassInventedWorkWithAnUnsetQuantity() {
        let invented = QuoteLine(title: "Installation", category: .labour, source: .voice, unit: "h")
        XCTAssertFalse(ExtractionChecks.problems([invented], expected: []).isEmpty)
    }
    func testCheckerRejectsWrongUnitsAndGuessedSupplyEvenWhenQuantityMatches() {
        var line = QuoteLine(title: "Install light fittings", category: .labour, source: .voice, quantity: 2, unit: "set")
        line.supply = .contractor
        let failures = ExtractionChecks.problems([line], expected: [.init("light", 2)])
        XCTAssertTrue(failures.contains { $0.contains("expected each") })
        XCTAssertTrue(failures.contains { $0.contains("material supply") })
    }
    func testInlineCorrectionUsesLastAffirmativeCount() {
        let parsed = NoteParser.parse("Replace six sockets, actually eight.")
        XCTAssertEqual(parsed.items.count, 1)
        XCTAssertEqual(parsed.items.first?.quantity, 8)
    }
    func testCompoundNumberAndElectricalRatingDoNotBecomeExtraCounts() {
        let parsed = NoteParser.parse("Replace twenty-one 13A sockets.")
        XCTAssertEqual(parsed.items.count, 1)
        XCTAssertEqual(parsed.items.first?.quantity, 21)
        XCTAssertEqual(parsed.items.first?.unit, "each")
        XCTAssertNil(NoteParser.parse("Replace the 13A sockets.").items.first?.quantity)
    }
    func testDecimalWordsAndExplicitSets() {
        XCTAssertEqual(NoteParser.parse("Allow one point five hours.").items.first?.quantity, Decimal(string: "1.5"))
        XCTAssertEqual(NoteParser.parse("Install two sets of lights.").items.first?.unit, "set")
    }
    func testSupplyNeverDefaultsToContractor() {
        let result = SourceExtraction.prepare("Install four new sockets.", source: .voice, recipes: JobRecipe.starters)
        XCTAssertEqual(result.lines.first?.supply, .unknown)
        XCTAssertEqual(NoteParser.parse("Supply two sockets.").items.first?.supply, .contractor)
    }
    func testNegationIsExcludedAndUndecidedWorkProducesNothing() {
        XCTAssertEqual(NoteParser.parse("Do not replace the two switches.").items.first?.disposition, .excluded)
        XCTAssertTrue(NoteParser.parse("The customer is undecided.").items.isEmpty)
        XCTAssertTrue(NoteParser.parse("No work requested.").items.isEmpty)
    }
    func testExplicitRoomCountsRemainSeparateWithoutRepeatingTheVerb() {
        let parsed = NoteParser.parse("Install 2 sockets in the kitchen and 3 sockets in the bedroom.")
        XCTAssertEqual(parsed.items.map(\.quantity), [2, 3])
        XCTAssertEqual(parsed.items.map(\.room), ["kitchen", "bedroom"])
    }
    func testTwoUnknownCountsAreNeverSilentlyCombined() {
        let parsed = NoteParser.parse("Install 2 lights with 3 switches.")
        XCTAssertNil(parsed.items.first?.quantity)
        XCTAssertFalse(parsed.warnings.isEmpty)
    }
    func testCatalogueCannotChangeFitIntoReplacement() {
        let parsed = NoteParser.parse("Fit one customer-supplied extractor fan.")
        let recipe = JobRecipe.starters.first { $0.name == "Replace extractor fan" }!
        XCTAssertFalse(NoteParser.compatible(recipe, with: parsed.items[0]))
    }
    func testUnpunctuatedVoiceKeepsTasksAndTimeSeparate() {
        let result = SourceExtraction.prepare("Replace six sockets install two light fittings approximately four hours", source: .voice, recipes: JobRecipe.starters)
        XCTAssertEqual(result.lines.map(\.quantity), [6, 2, 4])
        XCTAssertEqual(result.lines.map(\.unit), ["each", "each", "h"])
    }
    func testSupplyNegationDoesNotExcludeTheWholeInstallation() {
        let parsed = NoteParser.parse("Install two light fittings not supplied by the customer.")
        XCTAssertEqual(parsed.items.first?.disposition, .included)
        XCTAssertEqual(parsed.items.first?.supply, .unknown)
    }
    func testNoActionObservationCannotCreateAnInstallation() {
        XCTAssertTrue(NoteParser.parse("There are six existing sockets in the kitchen.").items.isEmpty)
    }
    func testReanalysisPreservesContractorVerifiedSpecifications() {
        var old = JobRecipe.starters[0].scopeLine(quantity: 6)
        old.specification = "White double sockets"; old.supply = .customer; old.isReviewed = true
        var incoming = JobRecipe.starters[0].scopeLine(quantity: 8)
        incoming.supply = .unknown
        let changes = WorkflowRules.reconcile([incoming], existing: [old])
        XCTAssertEqual(changes.first?.line.quantity, 8)
        XCTAssertEqual(changes.first?.line.specification, "White double sockets")
        XCTAssertEqual(changes.first?.line.supply, .customer)
    }

}
