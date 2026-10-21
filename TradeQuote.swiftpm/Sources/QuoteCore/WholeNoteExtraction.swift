import Foundation

/// The language model proposes relationships between literal quotes, never numeric facts.
public struct WorkEvidence: Sendable {
    public var sourceText: String
    public var objectText: String
    public var quantityText: String
    public var roomText: String
    public var instructionText: String
    public var supplyText: String
    public init(sourceText: String, objectText: String, quantityText: String = "", roomText: String = "",
                instructionText: String = "", supplyText: String = "") {
        self.sourceText = sourceText; self.objectText = objectText; self.quantityText = quantityText
        self.roomText = roomText; self.instructionText = instructionText; self.supplyText = supplyText
    }
}

public enum WholeNoteExtraction {
    public static func resolve(_ note: String, evidence: [WorkEvidence]) -> ParsedNote {
        var result = NoteParser.parse(note)
        if result.items.isEmpty && NoteParser.isUndecided(note) { return result }
        let conflictingAction = result.warnings.contains("Conflicting shared work instructions need confirmation.")
        let conflictingSupply = result.warnings.contains("Conflicting shared supply instructions need confirmation.")
        for proposed in evidence.prefix(20) {
            guard var item = grounded(proposed, in: note) else {
                result.warnings.append("An AI suggestion could not be linked to the original note and was ignored.")
                continue
            }
            if conflictingAction { item.action = ""; item.category = .labour }
            if conflictingSupply { item.supply = .unknown }
            let matches = result.items.indices.filter { index in
                let old = result.items[index]
                let oldKey = " " + NoteParser.objectKey(old.object) + " "
                let newKey = " " + NoteParser.objectKey(item.object) + " "
                let sameObject = oldKey.contains(newKey) || newKey.contains(oldKey) ||
                    (["h", "day"].contains(item.unit) && QuoteRules.unitsMatch(old.unit, item.unit))
                return sameObject && QuoteRules.unitsMatch(old.unit, item.unit) &&
                    (old.room == nil || item.room == nil || WorkflowRules.normalized(old.room ?? "") == WorkflowRules.normalized(item.room ?? ""))
            }
            if matches.count == 1, let index = matches.first {
                var old = result.items[index]
                if let quantity = item.quantity {
                    if old.quantity == nil { old.quantity = quantity; old.approximate = item.approximate }
                    else if old.quantity != quantity {
                        result.warnings.append("AI associated a different count with \(old.object). The source-parsed count was retained; check the evidence.")
                    }
                }
                if old.action.isEmpty { old.action = item.action; old.category = item.category }
                if old.room == nil { old.room = item.room }
                if old.supply == .unknown { old.supply = item.supply }
                if item.disposition != .included { old.disposition = item.disposition }
                let begin = min(old.sourceRange.location, item.sourceRange.location)
                let end = max(NSMaxRange(old.sourceRange), NSMaxRange(item.sourceRange))
                old.sourceRange = NSRange(location: begin, length: end - begin)
                old.excerpt = (note as NSString).substring(with: old.sourceRange)
                result.items[index] = old
            } else if matches.isEmpty {
                result.items.append(item)
            } else {
                result.warnings.append("Several work items match \(item.object). Their quantities were preserved separately for review.")
            }
        }
        // A successfully linked fragment should no longer be reported as unsupported.
        result.warnings.removeAll { warning in
            guard warning.hasPrefix("No direct work instruction recognised"),
                  let start = warning.firstIndex(of: "“"), let end = warning.lastIndex(of: "”"), start < end else { return false }
            let fragment = String(warning[warning.index(after: start)..<end])
            return result.items.contains { $0.excerpt.contains(fragment) }
        }
        return result
    }

    private static func grounded(_ evidence: WorkEvidence, in note: String) -> ParsedWork? {
        guard let sourceRange = literalRange(evidence.sourceText, in: note),
              !NoteParser.isUndecided(evidence.sourceText),
              let objectRange = literalRange(evidence.objectText, in: note, near: sourceRange.location),
              literalRange(evidence.objectText, in: evidence.sourceText) != nil,
              NoteParser.quantityFact(evidence.objectText) == nil else { return nil }
        let object = (note as NSString).substring(with: objectRange).lowercased()
        guard !["all", "parts", "all parts", "items", "materials", "everything", "them", "work"].contains(WorkflowRules.normalized(object)) else { return nil }
        var ranges = [sourceRange, objectRange]
        func quote(_ text: String) -> String? {
            guard !text.isEmpty, let range = literalRange(text, in: note, near: objectRange.location) else { return nil }
            ranges.append(range)
            return (note as NSString).substring(with: range)
        }
        // Nonempty but ungrounded fields invalidate a suggestion instead of silently accepting it.
        for text in [evidence.quantityText, evidence.roomText, evidence.instructionText, evidence.supplyText] where !text.isEmpty {
            guard literalRange(text, in: note) != nil else { return nil }
        }
        let quantityQuote = quote(evidence.quantityText)
        var quantity = quantityQuote.flatMap(NoteParser.quantityFact)
        if quantityQuote != nil && quantity == nil { return nil }
        // If AI quotes just 'four' from 'four hours', retain the adjacent explicit unit.
        if quantity?.unit == "each", let countRange = literalRange(evidence.quantityText, in: note, near: objectRange.location) {
            let remaining = (note as NSString).substring(from: NSMaxRange(countRange))
            let pattern = "^\\s+(?:(?:square\\s+)?(?:hours?|hrs?|h|days?|metres?|meters?|m²|m2|mm|cm|m|sets?|each|pieces?|pcs))\\b"
            if let unitRange = remaining.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               let extended = NoteParser.quantityFact(evidence.quantityText + remaining[unitRange]) {
                quantity = extended
                ranges.append(NSRange(location: countRange.location, length: countRange.length + (String(remaining[unitRange]) as NSString).length))
            }
        }
        let room = quote(evidence.roomText)
        let instruction = quote(evidence.instructionText)
        let fact = instruction.flatMap(NoteParser.actionFact)
        var action = fact?.action ?? ""
        let unit = quantity?.unit ?? "each"
        if ["h", "day"].contains(unit) && action.isEmpty { action = "allow" }
        let supplyQuote = quote(evidence.supplyText)
        var supply = supplyQuote.map(NoteParser.supplyFact) ?? .unknown
        let category: LineCategory = ["supply", "provide", "purchase"].contains(action) ? .materials : .labour
        if category == .materials && supply == .unknown { supply = .contractor }
        if ["h", "day"].contains(unit) { supply = .none }
        let combined = evidence.sourceText + " " + (instruction ?? "")
        var excluded = fact?.excluded == true
        if let instruction, let actionRange = literalRange(instruction, in: note, near: objectRange.location) {
            let prefix = (note as NSString).substring(to: actionRange.location).suffix(50)
            if regex("(?:do not|don't|not to|no need to|never|not)\\s*$", String(prefix)) { excluded = true }
        }
        let optional = regex("\\b(?:optionally|optional|maybe|perhaps|possibly)\\b", combined)
        let begin = ranges.map(\.location).min()!, end = ranges.map { NSMaxRange($0) }.max()!
        let span = NSRange(location: begin, length: end - begin)
        return ParsedWork(action: action, object: ["h", "day"].contains(unit) ? "labour allowance" : object,
            excerpt: (note as NSString).substring(with: span), sourceRange: span, quantity: quantity?.value, unit: unit,
            room: room?.trimmingCharacters(in: .whitespacesAndNewlines), category: category, supply: supply,
            disposition: excluded ? .excluded : optional ? .optional : .included,
            approximate: quantity?.approximate ?? false, isCorrection: false)
    }

    private static func literalRange(_ quote: String, in text: String, near anchor: Int = 0) -> NSRange? {
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: quote) + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range).min { abs($0.location - anchor) < abs($1.location - anchor) }
    }
    private static func regex(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
