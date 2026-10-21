import Foundation

/// Conservative English trade-note grammar. Quantities and scope qualifiers are source facts,
/// never generated numbers. Unsupported language/grammar is left for manual review.
public struct ParsedWork: Sendable {
    public var action: String
    public var object: String
    public var excerpt: String
    public var sourceRange: NSRange
    public var quantity: Decimal?
    public var unit: String
    public var room: String?
    public var category: LineCategory
    public var supply: MaterialSupply
    public var disposition: ScopeDisposition
    public var approximate: Bool
    public var isCorrection: Bool
    public var title: String {
        let text = action.isEmpty ? object : action + " " + object
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    public var identity: String { NoteParser.objectKey(object) + "|" + WorkflowRules.normalized(room ?? "") + "|" + unit }
}
public struct ParsedNote: Sendable {
    public var items: [ParsedWork]
    public var warnings: [String]
}
public enum NoteParser {
    private struct Token { var text: String; var range: NSRange }
    private static let actions = ["replace", "install", "fit", "repair", "swap", "change", "remove", "exclude", "allow", "supply", "provide", "purchase", "inspect", "test", "paint", "clean", "service", "rewire", "connect", "disconnect", "relocate", "move", "fix", "add", "mount"]
    private static let small: [String: Int] = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    private static let unitMap = ["hour": "h", "hours": "h", "hr": "h", "hrs": "h", "h": "h", "day": "day", "days": "day", "metre": "m", "metres": "m", "meter": "m", "meters": "m", "m": "m", "m2": "m²", "m²": "m²", "sqm": "m²", "mm": "mm", "cm": "cm", "set": "set", "sets": "set", "each": "each", "pieces": "each", "pcs": "each"]
    private static let numberPattern = "(?:[0-9]+(?:[.,][0-9]+)?(?:m²|m2|mm|cm|m|hrs?|h|x)?|" + small.keys.sorted().joined(separator: "|") + ")"

    public static func parse(_ note: String) -> ParsedNote {
        let original = note as NSString
        var boundaries: [NSRange] = matches("[;!?\\n]|(?<![0-9])[.,]|[.,](?![0-9])", in: note).map(\.range)
        let conjunction = "\\b(?:and|then)\\s+(?=(?:(?:also|optionally|approximately|about|roughly)\\s+)*(?:" + actions.joined(separator: "|") + "|" + numberPattern + ")\\b)"
        for match in matches(conjunction, in: note) {
            let before = original.substring(to: match.range.location)
            let previous = tokens(before).last?.text ?? ""
            if small[previous] == nil && previous != "hundred" && previous != "thousand" { boundaries.append(match.range) }
        }
        boundaries.sort { $0.location < $1.location }
        var spans: [NSRange] = [], cursor = 0
        for boundary in boundaries where boundary.location >= cursor {
            if boundary.location > cursor { spans.append(NSRange(location: cursor, length: boundary.location - cursor)) }
            cursor = NSMaxRange(boundary)
        }
        if cursor < original.length { spans.append(NSRange(location: cursor, length: original.length - cursor)) }
        spans = splitUnpunctuated(spans, original: original)
        var result: [ParsedWork] = [], warnings: [String] = []
        var previous: ParsedWork?
        for rawSpan in spans {
            let raw = original.substring(with: rawSpan)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let leading = (raw as NSString).range(of: trimmed).location
            let span = NSRange(location: rawSpan.location + leading, length: (trimmed as NSString).length)
            let ts = tokens(trimmed)
            guard !ts.isEmpty else { continue }
            // These are explicitly undecided observations, not requests to install anything.
            if contains("\\b(?:not decided|undecided|no work (?:requested|required)|not sure what work|considering whether)\\b", trimmed) { continue }
            if ts.first?.text == "not", !ts.contains(where: { actions.contains($0.text) }) { continue } // e.g. correction tail: "not six"
            let correction = contains("\\b(?:correction|actually|instead|make that|change (?:it|that) to)\\b", trimmed)
            let actionToken = ts.firstIndex { actions.contains($0.text) }
            let timeUnit = ts.firstIndex { ["h", "hr", "hrs", "hour", "hours", "day", "days"].contains($0.text) }
            var action = actionToken.map { ts[$0].text }
            if action == nil && timeUnit != nil { action = "allow" }
            if action == nil, let previous, (firstNumber(ts) != nil || correction) {
                let gap = original.substring(with: NSRange(location: NSMaxRange(previous.sourceRange),
                    length: max(0, span.location - NSMaxRange(previous.sourceRange))))
                // Only a connected list or an explicit correction inherits the previous verb.
                if correction || contains("^\\s*(?:and|then)\\s*$", gap) { action = previous.action }
            }
            // Quantity-led shorthand is useful evidence, but does not establish an action.
            // Review must ask the contractor instead of inventing installation/replacement.
            let listTokens = Array(ts.drop(while: { ["optional", "optionally", "approximately", "about", "roughly"].contains($0.text) }))
            if action == nil, firstNumber(listTokens)?.indices.lowerBound == 0 { action = "" }
            guard let request = action else {
                warnings.append("No direct work instruction recognised in: “\(trimmed)”. Add any intended work manually.")
                continue
            }
            let start = actionToken.map { $0 + 1 } ?? 0
            var body = Array(ts.dropFirst(start))
            var isApproximate = contains("\\b(?:approximately|approx|about|around|roughly|estimated|estimate|circa)\\b", trimmed)
            var disposition: ScopeDisposition = contains("\\b(?:optionally|optional|maybe|perhaps|possibly)\\b", trimmed) ? .optional : .included
            let actionPrefix = actionToken.map { (trimmed as NSString).substring(to: ts[$0].range.location) } ?? ""
            if request == "exclude" || contains("(?:do not|don't|not to|no need to|never|not)\\s*$", actionPrefix) { disposition = .excluded }
            let supply = explicitSupply(trimmed, materialInstruction: ["supply", "provide", "purchase"].contains(request))
            let category: LineCategory = ["supply", "provide", "purchase"].contains(request) ? .materials : .labour
            let room = roomName(in: trimmed)
            let locationIndex = body.firstIndex { ["in", "at", "inside", "outside"].contains($0.text) }
            let quantityTokens = locationIndex.map { Array(body.prefix($0)) } ?? body
            let candidates = numberMentions(quantityTokens)
            var quantity: Decimal? = nil
            var quantityRange: Range<Int>?
            var unit = "each"
            if candidates.count == 1, let number = candidates.first {
                if number.value > 0 && number.value <= 10000 { quantity = number.value }
                quantityRange = number.indices
                unit = number.attachedUnit ?? "each"
                if number.indices.upperBound < quantityTokens.count {
                    let next = quantityTokens[number.indices.upperBound].text
                    unit = unitMap[next] ?? unit
                    if next == "square", number.indices.upperBound + 1 < quantityTokens.count,
                       ["metres", "meters", "metre", "meter"].contains(quantityTokens[number.indices.upperBound + 1].text) { unit = "m²" }
                }
            } else if candidates.count > 1 {
                // A negated old quantity in a correction is not the new value.
                let positive = candidates.filter { number in
                    !quantityTokens.prefix(number.indices.lowerBound).suffix(2).contains(where: { $0.text == "not" })
                }
                if positive.count == 1, let number = positive.first {
                    quantity = number.value > 0 && number.value <= 10000 ? number.value : nil
                    quantityRange = number.indices
                    if number.indices.upperBound < quantityTokens.count { unit = unitMap[quantityTokens[number.indices.upperBound].text] ?? "each" }
                } else { warnings.append("Several quantities need confirmation in: “\(trimmed)”. No quantity was chosen.") }
            }
            // An explicit singular article is a count, but only in the work-object position.
            if candidates.isEmpty, let first = body.first, ["a", "an"].contains(first.text) {
                quantity = 1; quantityRange = 0..<1
            }
            if let timeUnit, let mapped = unitMap[ts[timeUnit].text] { unit = mapped }
            if quantityRange != nil, let range = quantityRange, range.upperBound <= body.count { body.removeSubrange(range) }
            let fillers: Set<String> = ["the", "a", "an", "also", "approximately", "approx", "about", "around", "roughly", "actually", "correction", "instead", "optionally", "optional", "customer", "supplied", "contractor", "provided", "by", "our", "we", "will", "i", "to", "that", "it"]
            body = body.filter { !fillers.contains($0.text) }
            if let at = body.firstIndex(where: { ["in", "at", "inside", "outside", "from", "not"].contains($0.text) }) { body = Array(body.prefix(at)) }
            body.removeAll { unitMap[$0.text] != nil || $0.text == "square" }
            // Strip explicit supply wording, without turning it into a material purchase.
            if let supplied = body.firstIndex(where: { ["supplies", "supply", "provides"].contains($0.text) }) { body = Array(body.prefix(supplied)) }
            var object = body.map(\.text).joined(separator: " ")
            if ["h", "day"].contains(unit) {
                object = "labour allowance"
                if !isApproximate { isApproximate = contains("\\b(?:approximately|about|roughly)\\b", trimmed) }
            }
            var evidence = trimmed, evidenceRange = span
            if object.isEmpty, let previous, correction || (!request.isEmpty && quantity != nil) {
                object = previous.object
                if !["h", "day"].contains(unit) { unit = previous.unit }
                // The earlier object and the correction are both retained as literal evidence.
                let begin = previous.sourceRange.location
                let end = NSMaxRange(span)
                evidenceRange = NSRange(location: begin, length: end - begin)
                evidence = original.substring(with: evidenceRange)
            }
            guard !object.isEmpty else {
                warnings.append("Work object needs confirmation in: “\(trimmed)”.")
                continue
            }
            var item = ParsedWork(action: canonicalAction(request), object: object, excerpt: evidence,
                sourceRange: evidenceRange, quantity: quantity, unit: unit, room: room,
                category: ["h", "day"].contains(unit) ? .labour : category, supply: ["h", "day"].contains(unit) ? .none : supply,
                disposition: disposition, approximate: isApproximate, isCorrection: correction)
            if correction {
                let same = result.indices.filter { result[$0].identity == item.identity }
                if same.count == 1, let index = same.first {
                    let begin = result[index].sourceRange.location
                    item.sourceRange = NSRange(location: begin, length: NSMaxRange(span) - begin)
                    item.excerpt = original.substring(with: item.sourceRange)
                    result[index] = item; previous = item; continue
                }
            }
            result.append(item); previous = item
        }
        return ParsedNote(items: result, warnings: warnings)
    }

    private static func splitUnpunctuated(_ spans: [NSRange], original: NSString) -> [NSRange] {
        var result: [NSRange] = []
        for span in spans {
            let text = original.substring(with: span)
            let ts = tokens(text)
            let verbs = ts.indices.filter { actions.contains(ts[$0].text) }
            var breaks: Set<Int> = []
            for index in verbs.dropFirst() {
                var location = ts[index].range.location
                if index > 0 && ["actually", "correction", "instead"].contains(ts[index - 1].text) { location = ts[index - 1].range.location }
                breaks.insert(location)
            }
            for number in numberMentions(ts) {
                let after = number.indices.upperBound
                let time = number.attachedUnit == "h" || number.attachedUnit == "day" ||
                    (after < ts.count && ["hour", "hours", "h", "hr", "hrs", "day", "days"].contains(ts[after].text))
                guard time, let previousVerb = verbs.last(where: { $0 < number.indices.lowerBound }), ts[previousVerb].text != "allow" else { continue }
                var start = number.indices.lowerBound
                if start > 0 && ["approximately", "about", "roughly", "around"].contains(ts[start - 1].text) { start -= 1 }
                if start > previousVerb + 1 { breaks.insert(ts[start].range.location) }
            }
            var cursor = 0
            for position in breaks.sorted() where position > cursor {
                result.append(NSRange(location: span.location + cursor, length: position - cursor))
                cursor = position
            }
            if cursor < span.length { result.append(NSRange(location: span.location + cursor, length: span.length - cursor)) }
        }
        return result
    }

    public static func compatible(_ recipe: JobRecipe, with item: ParsedWork) -> Bool {
        guard !item.action.isEmpty else { return false }
        guard QuoteRules.unitsMatch(recipe.unit, item.unit) else { return false }
        if ["h", "day"].contains(item.unit) { return true }
        let recipeAction = recipe.name.lowercased().split(separator: " ").first.map(String.init) ?? ""
        return canonicalAction(recipeAction) == item.action
    }
    public static func objectKey(_ value: String) -> String {
        WorkflowRules.normalized(value).split(separator: " ").map { raw in
            let word = String(raw)
            if word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
            return word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
        }.joined(separator: " ")
    }
    private static func canonicalAction(_ value: String) -> String {
        switch value { case "swap", "change": "replace"; case "fit", "mount", "add": "install"; case "exclude": "exclude"; default: value }
    }
    private static func explicitSupply(_ text: String, materialInstruction: Bool) -> MaterialSupply {
        let customer = contains("\\b(?:customer[ -](?:supplied|provided)|(?:supplied|provided) by (?:the )?(?:customer|client)|(?:customer|client) (?:supplies|provides|will supply|will provide))\\b", text)
        let contractor = contains("\\b(?:contractor[ -](?:supplied|provided)|(?:supplied|provided) by (?:the )?(?:contractor|electrician)|(?:we|i|contractor) (?:supply|supplies|provide|provides|will supply|will provide))\\b", text)
        if contains("\\bnot\\s+(?:customer[ -]supplied|contractor[ -]supplied|supplied by|provided by)\\b", text) { return .unknown }
        if customer && contractor { return .unknown }
        if customer { return .customer }
        if contractor || materialInstruction { return .contractor }
        return .unknown
    }
    private static func roomName(in text: String) -> String? {
        guard let match = matches("\\b(?:in|at|inside)\\s+(?:the\\s+)?([\\p{L}0-9 -]+?)(?=\\s+(?:and|with|using|supplied|provided|for|not)\\b|$)", in: text).first else { return nil }
        return (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }
    private static func tokens(_ text: String) -> [Token] {
        matches("[0-9]+(?:[.,][0-9]+)?(?:[\\p{L}²]+[0-9]*)?|[\\p{L}\\p{N}]+(?:['’][\\p{L}]+)?", in: text).map {
            Token(text: (text as NSString).substring(with: $0.range).lowercased(), range: $0.range)
        }
    }
    private struct NumberMention { var value: Decimal; var indices: Range<Int>; var attachedUnit: String? }
    private static func firstNumber(_ tokens: [Token]) -> NumberMention? { numberMentions(tokens).first }
    private static func numberMentions(_ tokens: [Token]) -> [NumberMention] {
        var result: [NumberMention] = [], i = 0
        while i < tokens.count {
            let token = tokens[i].text
            if let match = matches("^([0-9]+(?:[.,][0-9]+)?)(m²|m2|mm|cm|m|hrs?|h|x)?$", in: token).first {
                let valueText = (token as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                if let value = Decimal(string: valueText, locale: Locale(identifier: "en_US_POSIX")) {
                    let suffix = match.range(at: 2).location == NSNotFound ? nil : (token as NSString).substring(with: match.range(at: 2))
                    result.append(NumberMention(value: value, indices: i..<(i + 1), attachedUnit: suffix.flatMap { unitMap[$0] }))
                }
                i += 1; continue
            }
            if small[token] != nil {
                let start = i
                var total = 0, group = 0
                while i < tokens.count {
                    let word = tokens[i].text
                    if let digit = small[word] { group += digit }
                    else if word == "hundred" { group = max(group, 1) * 100 }
                    else if word == "thousand" { total += max(group, 1) * 1000; group = 0 }
                    else if word == "and", i + 1 < tokens.count, small[tokens[i + 1].text] != nil { i += 1; continue }
                    else { break }
                    i += 1
                }
                var value = Decimal(total + group)
                if i + 1 < tokens.count, tokens[i].text == "point" {
                    var fraction = "", j = i + 1
                    while j < tokens.count, let digit = small[tokens[j].text], digit < 10 { fraction += String(digit); j += 1 }
                    if !fraction.isEmpty, let decimal = Decimal(string: "\(total + group).\(fraction)") { value = decimal; i = j }
                }
                result.append(NumberMention(value: value, indices: start..<i))
                continue
            }
            i += 1
        }
        return result
    }
    private static func contains(_ pattern: String, _ text: String) -> Bool { !matches(pattern, in: text).isEmpty }
    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
