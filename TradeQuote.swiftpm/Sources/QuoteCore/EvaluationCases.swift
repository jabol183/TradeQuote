import Foundation

public struct ExpectedWork: Sendable {
    public var keyword: String
    public var quantity: Decimal?
    public var unit: String
    public var room: String?
    public var supply: MaterialSupply
    public var disposition: ScopeDisposition
    public var approximate: Bool
    public var actionRequired: Bool
    public var action: String?
    public init(_ keyword: String, _ quantity: Decimal?, unit: String = "each", room: String? = nil,
                supply: MaterialSupply = .unknown, disposition: ScopeDisposition = .included, approximate: Bool = false, actionRequired: Bool = false, action: String? = nil) {
        self.keyword = keyword; self.quantity = quantity; self.unit = unit; self.room = room
        self.supply = supply; self.disposition = disposition; self.approximate = approximate
        self.actionRequired = actionRequired
        self.action = action
    }
}
public struct ExtractionExample: Identifiable, Sendable {
    public var id: String
    public var note: String
    public var expected: [ExpectedWork]
    public init(_ id: String, _ note: String, _ expected: [ExpectedWork]) { self.id = id; self.note = note; self.expected = expected }
    public static let cases: [ExtractionExample] = [
        .init("Basic visit", "Replace six sockets, install two light fittings, approximately four hours.", [
            .init("socket", 6), .init("light", 2), .init("labour", 4, unit: "h", supply: .none, approximate: true)]),
        .init("Correction", "Replace six sockets. Correction: replace eight sockets, not six.", [.init("socket", 8)]),
        .init("Customer supply", "Install two ceiling light fittings supplied by the customer.", [.init("light", 2, supply: .customer)]),
        .init("Optional extra", "Replace three sockets. Optionally replace one light switch.", [.init("socket", 3), .init("switch", 1, disposition: .optional)]),
        .init("Room separation", "Replace two sockets in the kitchen and three sockets in the bedroom.", [.init("socket", 2, room: "kitchen"), .init("socket", 3, room: "bedroom")]),
        .init("Missing quantity", "Replace the damaged sockets in the kitchen.", [.init("socket", nil, room: "kitchen")]),
        .init("Decimal allowance", "Allow 1.5 hours for electrical fault finding.", [.init("labour", Decimal(string: "1.5"), unit: "h", supply: .none)]),
        .init("Exclusion", "Replace two sockets. Exclude the three light fittings from this quote.", [.init("socket", 2), .init("light", 3, disposition: .excluded)]),
        .init("No purchase inference", "Fit one customer-supplied extractor fan in the bathroom.", [.init("fan", 1, room: "bathroom", supply: .customer)]),
        .init("No work", "The customer has not decided what work they want yet.", []),
        .init("Item list — choose action", "2 double sockets in living room\n2 light switches in the kitchen", [
            .init("double socket", 2, room: "living room", actionRequired: true),
            .init("light switch", 2, room: "kitchen", actionRequired: true)]),
        .init("Shared instruction — screenshot", "Two double sockets in the kitchen one light switch in the living room\nReplace all parts provided by customer", [
            .init("double socket", 2, room: "kitchen", supply: .customer, action: "replace"),
            .init("light switch", 1, room: "living room", supply: .customer, action: "replace")]),
        .init("Shared instruction first", "Replace all parts provided by customer. Two double sockets in the kitchen one light switch in the living room", [
            .init("double socket", 2, room: "kitchen", supply: .customer, action: "replace"),
            .init("light switch", 1, room: "living room", supply: .customer, action: "replace")]),
        .init("Shared details in separate sentences", "Two double sockets in the kitchen. One light switch in the living room. Replace them all. All parts are provided by customer.", [
            .init("double socket", 2, room: "kitchen", supply: .customer, action: "replace"),
            .init("light switch", 1, room: "living room", supply: .customer, action: "replace")])
    ]
    /// These cases specifically require relationship extraction on Apple hardware.
    public static let languageCases: [ExtractionExample] = [
        .init("Count in another sentence", "Replace the sockets in the kitchen. There are two of them. The customer will provide the parts.", [
            .init("socket", 2, room: "kitchen", supply: .customer, action: "replace")]),
        .init("Two distant counts", "Replace the kitchen sockets. There are two. Replace the living room switch. There is one. All parts provided by customer.", [
            .init("socket", 2, room: "kitchen", supply: .customer, action: "replace"),
            .init("switch", 1, room: "living room", supply: .customer, action: "replace")])
    ]
    public static var allCases: [ExtractionExample] { cases + languageCases }
}
public enum ExtractionChecks {
    /// Empty quantities are not evidence of zero work: item coverage and every fact are checked.
    public static func problems(_ lines: [QuoteLine], expected: [ExpectedWork]) -> [String] {
        var failures: [String] = []
        if lines.count != expected.count { failures.append("Expected \(expected.count) work items; got \(lines.count).") }
        var unused = Array(lines.indices)
        for wanted in expected {
            let keyword = NoteParser.objectKey(wanted.keyword)
            let candidates = unused.filter { index in
                NoteParser.objectKey(lines[index].title).contains(keyword) &&
                WorkflowRules.normalized(lines[index].room ?? "") == WorkflowRules.normalized(wanted.room ?? "")
            }
            guard let index = candidates.first else { failures.append("Missing \(wanted.keyword)\(wanted.room.map { " in " + $0 } ?? "")."); continue }
            unused.removeAll { $0 == index }
            let line = lines[index]
            if line.quantity != wanted.quantity { failures.append("\(wanted.keyword): wrong/missing quantity.") }
            if !QuoteRules.unitsMatch(line.unit, wanted.unit) { failures.append("\(wanted.keyword): expected \(wanted.unit), got \(line.unit).") }
            if (line.supply ?? .unknown) != wanted.supply { failures.append("\(wanted.keyword): incorrect material supply.") }
            if (line.disposition ?? .included) != wanted.disposition { failures.append("\(wanted.keyword): incorrect included/optional/excluded status.") }
            if (line.isApproximate ?? false) != wanted.approximate { failures.append("\(wanted.keyword): incorrect approximation flag.") }
            if (line.workActionRequired ?? false) != wanted.actionRequired { failures.append("\(wanted.keyword): incorrect missing-action status.") }
            if let action = wanted.action, NoteParser.actionFact(line.title)?.action != action { failures.append("\(wanted.keyword): incorrect requested work.") }
            if line.category != .labour { failures.append("\(wanted.keyword): invented material purchase/category.") }
        }
        if !unused.isEmpty { failures.append("Unexpected work items: " + unused.map { lines[$0].title }.joined(separator: ", ")) }
        return failures
    }
}
