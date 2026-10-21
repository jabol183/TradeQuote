import Foundation

public enum LabourBilling: String, Codable, CaseIterable, Sendable {
    case perTask = "Per task", hourly = "Hourly", fixed = "Fixed labour total"
}
public enum ScopeDisposition: String, Codable, CaseIterable, Sendable {
    case included = "Included", optional = "Optional", excluded = "Excluded"
}
public enum MaterialSupply: String, Codable, CaseIterable, Sendable {
    case unknown = "Confirm supply", contractor = "Contractor", customer = "Customer", none = "No materials"
}
public enum ConfirmationKind: String, Codable, CaseIterable, Sendable {
    case specification = "Specification", quantity = "Quantity", supply = "Material supply", instruction = "Requested work"
}
public enum WorkAction: String, CaseIterable, Sendable {
    case install = "Install", replace = "Replace", repair = "Repair", remove = "Remove"
    case inspect = "Inspect", test = "Test", supply = "Supply", connect = "Connect"
    case relocate = "Relocate", rewire = "Rewire", service = "Service", paint = "Paint", clean = "Clean"
}
public enum PhotoPurpose: String, Codable, CaseIterable, Sendable {
    case evidence = "Supporting evidence", installation = "Existing installation", replacement = "Item to replace"
    case label = "Product label", access = "Access / location"
}
public struct PhotoContext: Codable, Identifiable, Equatable, Sendable {
    public var filename: String
    public var purpose: PhotoPurpose = .evidence
    public var instruction: String = ""
    public var lineID: UUID?
    public var id: String { filename }
    public init(filename: String) { self.filename = filename }
}
public struct PhotoObservation: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var filename: String
    public var text: String
    public var promotedLineID: UUID?
    public init(filename: String, text: String) { self.filename = filename; self.text = text }
}
public struct RecipeComponent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var category: LineCategory
    public var unit: String
    public var quantityPerJob: Decimal
    public var rateID: UUID?
    public init(title: String, category: LineCategory, unit: String = "each", quantityPerJob: Decimal = 1, rateID: UUID? = nil) {
        self.title = title; self.category = category; self.unit = unit; self.quantityPerJob = quantityPerJob; self.rateID = rateID
    }
}
public struct JobRecipe: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var unit: String
    public var specificationQuestion: String
    public var asksSupply: Bool
    public var inclusions: String
    public var exclusions: String
    public var components: [RecipeComponent]
    public init(id: UUID = UUID(), name: String, aliases: [String] = [], unit: String = "each",
                specificationQuestion: String = "", asksSupply: Bool = true, inclusions: String = "",
                exclusions: String = "", components: [RecipeComponent] = []) {
        self.id = id; self.name = name; self.aliases = aliases; self.unit = unit
        self.specificationQuestion = specificationQuestion; self.asksSupply = asksSupply
        self.inclusions = inclusions; self.exclusions = exclusions; self.components = components
    }
    public func scopeLine(quantity: Decimal? = nil) -> QuoteLine {
        var line = QuoteLine(title: name, category: .labour, source: .manual, quantity: quantity, unit: unit,
                             confirmationPrompt: specificationQuestion.isEmpty ? nil : specificationQuestion)
        line.recipeID = id
        line.confirmationKind = specificationQuestion.isEmpty ? nil : .specification
        line.supply = asksSupply ? .unknown : MaterialSupply.none
        return line
    }
    public static let starters: [JobRecipe] = {
        let jobs: [(String, [String], String, Bool)] = [
            ("Replace existing socket", ["swap socket", "replace socket", "change socket", "sockets"], "Single or double socket, and which finish?", true),
            ("Install light fitting", ["light fitting", "light fittings", "ceiling light", "pendant"], "Which fitting and where will it be installed?", true),
            ("Install new socket point", ["new socket", "extra socket", "additional socket"], "Confirm location, specification and cable route.", true),
            ("Replace light switch", ["switch", "switches"], "Confirm switch type, gangs and finish.", true),
            ("Install outdoor light", ["outdoor light", "security light", "floodlight"], "Confirm fitting, location and access.", true),
            ("Install downlight", ["downlight", "downlights", "spotlight"], "Confirm fitting specification and location.", true),
            ("Replace extractor fan", ["extractor fan", "bathroom fan"], "Confirm fan specification and existing installation.", true),
            ("Install smoke alarm", ["smoke alarm", "smoke detector"], "Confirm alarm type, interconnection and location.", true),
            ("Replace consumer unit", ["consumer unit", "fuse box"], "Confirm assessed scope, board specification and testing requirements.", true),
            ("Install electric hob", ["hob", "cooker connection"], "Confirm appliance specification and existing supply.", true),
            ("Install EV charge point", ["ev charger", "charge point", "wallbox"], "Confirm charger, assessed supply and cable route.", true),
            ("Electrical fault finding", ["fault finding", "diagnose", "tripping"], "Confirm the reported issue and investigation scope.", false),
            ("Electrical inspection", ["inspection", "eicr"], "Confirm property and agreed inspection scope.", false),
            ("Replace isolator", ["isolator"], "Confirm isolator specification and location.", true),
            ("Install data point", ["data point", "ethernet", "network socket"], "Confirm point specification and cable route.", true),
            ("Electrical labour allowance", ["labour", "hours", "hour"], "", false)
        ]
        return jobs.enumerated().map { index, job in
            // Stable IDs make saved recipe references survive launches and upgrades.
            let id = UUID(uuidString: String(format: "A1700000-0000-4000-8000-%012d", index + 1))!
            return JobRecipe(id: id, name: job.0, aliases: job.1, unit: index == 15 ? "h" : "each",
                             specificationQuestion: job.2, asksSupply: job.3)
        }
    }()
}
public struct QuoteVersion: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var reason: String
    public var lines: [QuoteLine]
    public var observations: [PhotoObservation]
    public init(reason: String, lines: [QuoteLine], observations: [PhotoObservation]) {
        self.reason = reason; self.lines = lines; self.observations = observations
    }
}
public enum ChangeOperation: String, Sendable { case add, update, remove, conflict }
public struct DraftChange: Identifiable, Sendable {
    public var id = UUID()
    public var operation: ChangeOperation
    public var existingID: UUID?
    public var line: QuoteLine
    public var explanation: String
    public init(operation: ChangeOperation, existingID: UUID? = nil, line: QuoteLine, explanation: String) {
        self.operation = operation; self.existingID = existingID; self.line = line; self.explanation = explanation
    }
}
public enum WorkflowRules {
    public static func included(_ line: QuoteLine) -> Bool {
        switch line.disposition ?? .included {
        case .included: true
        case .optional: line.optionalSelected == true
        case .excluded: false
        }
    }
    public static func isChargeable(_ line: QuoteLine, in quote: Quote) -> Bool {
        guard included(line), line.isRecipeContainer != true else { return false }
        if line.category == .materials { return line.supply != .customer && line.supply != MaterialSupply.none }
        switch quote.billingMethod {
        case .hourly: return QuoteRules.normalizedUnit(line.unit) == "h"
        case .perTask: return QuoteRules.normalizedUnit(line.unit) != "h"
        case .fixed: return false
        case nil: return true // Preserve approved v1 documents and old drafts.
        }
    }
    public static func needsSpecification(_ line: QuoteLine) -> Bool {
        guard line.confirmationPrompt != nil else { return false }
        return line.confirmationKind == nil || line.confirmationKind == .specification || line.confirmationKind == .instruction
    }
    public static func canConfirm(_ line: QuoteLine) -> Bool {
        line.workActionRequired != true && !line.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (line.quantity ?? 0) > 0 && !line.unit.isEmpty &&
        (!needsSpecification(line) || !line.specification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (line.recipeID == nil || line.supply != .unknown) && line.needsRateMatch != true
    }
    /// A manual choice establishes the missing action; captured counts/evidence stay intact.
    public static func choosingAction(_ action: WorkAction, for original: QuoteLine) -> QuoteLine {
        guard original.workActionRequired == true else { return original }
        var line = original
        line.title = action.rawValue + " " + (line.capturedWorkObject ?? line.title)
        line.workActionRequired = false
        line.category = action == .supply ? .materials : .labour
        if action == .supply { line.supply = .contractor }
        if line.confirmationKind == .instruction {
            line.confirmationPrompt = nil; line.confirmationKind = nil
        }
        line.isReviewed = false; line.rateID = nil; line.approvedUnitPrice = nil
        return line
    }
    public static func searchRecipes(_ text: String, recipes: [JobRecipe], limit: Int = 5) -> [JobRecipe] {
        let query = normalized(text)
        let tokens = Set(query.split(separator: " ").map(String.init))
        var scored: [(recipe: JobRecipe, score: Int)] = []
        for recipe in recipes {
            var best = 0
            for phrase in [recipe.name] + recipe.aliases {
                let key = normalized(phrase)
                let words = Set(key.split(separator: " ").map(String.init))
                let common = words.intersection(tokens).count
                let score = query.contains(key) ? 100 + key.count : common
                best = max(best, score)
            }
            if best > 0 { scored.append((recipe: recipe, score: best)) }
        }
        scored.sort { a, b in
            if a.score == b.score { return a.recipe.name < b.recipe.name }
            return a.score > b.score
        }
        return scored.prefix(limit).map { $0.recipe }
    }
    public static func suggestedRates(for line: QuoteLine, rates: [Rate]) -> [Rate] {
        let tokens = Set(normalized(line.title).split(separator: " ").map(String.init))
        var scored: [(rate: Rate, score: Int)] = []
        for rate in rates where rate.category == line.category && QuoteRules.unitsMatch(rate.unit, line.unit) {
            let text = ([rate.name] + (rate.aliases ?? [])).joined(separator: " ")
            let words = Set(normalized(text).split(separator: " ").map(String.init))
            scored.append((rate: rate, score: words.intersection(tokens).count))
        }
        scored.sort { a, b in
            if a.score == b.score { return a.rate.name < b.rate.name }
            return a.score > b.score
        }
        return scored.map { $0.rate }
    }
    public static func normalized(_ value: String) -> String {
        value.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_GB"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func reconcile(_ incoming: [QuoteLine], existing: [QuoteLine], removals: [UUID] = []) -> [DraftChange] {
        var changes: [DraftChange] = []
        for id in Set(removals) {
            if let line = existing.first(where: { $0.id == id }) {
                changes.append(DraftChange(operation: .remove, existingID: id, line: line, explanation: "Remove this item?"))
            }
        }
        var seen = Set<String>()
        for proposed in incoming {
            let key = "\(proposed.recipeID?.uuidString ?? normalized(proposed.title))|\(normalized(proposed.room ?? ""))|\(proposed.category.rawValue)|\(QuoteRules.normalizedUnit(proposed.unit))"
            guard seen.insert(key).inserted else {
                changes.append(DraftChange(operation: .conflict, line: proposed, explanation: "Repeated work in this input. Choose which item to keep; no quantities were added together."))
                continue
            }
            let matches = existing.filter { old in
                let capturedMatch = (proposed.workActionRequired == true || old.workActionRequired == true) && old.capturedWorkObject != nil &&
                    normalized(old.capturedWorkObject ?? "") == normalized(proposed.capturedWorkObject ?? "")
                return QuoteRules.unitsMatch(old.unit, proposed.unit) &&
                normalized(old.room ?? "") == normalized(proposed.room ?? "") &&
                (capturedMatch || (old.category == proposed.category &&
                    ((old.recipeID != nil && old.recipeID == proposed.recipeID) || normalized(old.title) == normalized(proposed.title))))
            }
            if matches.count == 1, let old = matches.first {
                var revised = proposed
                // The source still omits an action; it cannot erase a manual choice made in Review.
                if proposed.workActionRequired == true, old.workActionRequired == false {
                    revised.title = old.title; revised.category = old.category; revised.recipeID = old.recipeID
                    revised.workActionRequired = false
                    revised.confirmationPrompt = old.confirmationPrompt; revised.confirmationKind = old.confirmationKind
                    if revised.supply == .unknown || revised.supply == nil { revised.supply = old.supply }
                }
                // Reanalysis cannot erase details the contractor already verified just because
                // a later note omits them. Explicit source changes still require a change preview.
                if old.isReviewed {
                    if revised.specification.isEmpty { revised.specification = old.specification }
                    if revised.supply == .unknown || revised.supply == nil { revised.supply = old.supply }
                }
                if normalized(old.title) == normalized(revised.title) && old.category == revised.category &&
                    old.recipeID == revised.recipeID && (old.workActionRequired ?? false) == (revised.workActionRequired ?? false) &&
                    old.quantity == revised.quantity && old.specification == revised.specification &&
                    (old.disposition ?? .included) == (revised.disposition ?? .included) && old.supply == revised.supply { continue }
                revised.id = old.id
                revised.rateID = old.rateID
                revised.linkedPhotos = Array(Set((old.linkedPhotos ?? []) + (proposed.linkedPhotos ?? [])))
                changes.append(DraftChange(operation: .update, existingID: old.id, line: revised,
                    explanation: "Update \(old.title): \(old.quantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "?") → \(proposed.quantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "?") \(old.unit). Review changed details."))
            } else if matches.count > 1 {
                changes.append(DraftChange(operation: .conflict, line: proposed, explanation: "Several existing items match. Select an item manually to avoid a duplicate."))
            } else {
                changes.append(DraftChange(operation: .add, line: proposed, explanation: "Add proposed work item"))
            }
        }
        return changes
    }
}
