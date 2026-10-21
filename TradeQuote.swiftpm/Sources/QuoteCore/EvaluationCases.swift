import Foundation

public struct ExtractionExample: Identifiable, Sendable {
    public var id: String
    public var note: String
    public var quantities: [Decimal]
    public init(_ id: String, _ note: String, _ quantities: [Decimal]) { self.id = id; self.note = note; self.quantities = quantities }
    public static let cases: [ExtractionExample] = [
        .init("Basic visit", "Replace six sockets, install two light fittings, approximately four hours.", [6, 2, 4]),
        .init("Correction", "Replace six sockets. Correction: replace eight sockets, not six.", [8]),
        .init("Customer supply", "Install two ceiling light fittings supplied by the customer.", [2]),
        .init("Optional extra", "Replace three sockets. Optionally replace one light switch.", [3, 1]),
        .init("Room separation", "Replace two sockets in the kitchen and three sockets in the bedroom.", [2, 3]),
        .init("Missing quantity", "Replace the damaged sockets in the kitchen.", []),
        .init("Decimal allowance", "Allow 1.5 hours for electrical fault finding.", [Decimal(string: "1.5")!]),
        .init("Exclusion", "Replace two sockets. Exclude the three light fittings from this quote.", [2, 3]),
        .init("No purchase inference", "Fit one customer-supplied extractor fan in the bathroom.", [1]),
        .init("No work", "The customer has not decided what work they want yet.", [])
    ]
}
