import Foundation

public enum LineCategory: String, Codable, CaseIterable, Sendable {
    case labour = "Labour"
    case materials = "Materials"
}

public enum EvidenceSource: String, Codable, Sendable {
    case voice = "Voice"
    case photo = "Photo"
    case manual = "Manual"
}

public enum QuoteStatus: String, Codable, CaseIterable, Sendable {
    case draft = "Draft"
    case final = "Ready"
    case sent = "Sent"
    case accepted = "Accepted"
    case declined = "Declined"
}

public struct Rate: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: LineCategory
    public var unit: String
    public var amount: Decimal?

    public init(id: UUID = UUID(), name: String, category: LineCategory, unit: String, amount: Decimal? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.unit = unit
        self.amount = amount
    }
}

public struct Customer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var email: String
    public var phone: String
    public var address: String

    public init(id: UUID = UUID(), name: String = "", email: String = "", phone: String = "", address: String = "") {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
    }
}

public struct BusinessProfile: Codable, Equatable, Sendable {
    public var name: String = ""
    public var email: String = ""
    public var address: String = ""
    public var telephone: String = ""
    public var taxIdentifier: String = ""
    /// nil means unconfigured, 0 means deliberately exempt/zero rate.
    public var vatPercent: Decimal? = nil
    public var currencyCode: String = "GBP"
    public var terms: String = "Valid for 30 days. Work subject to site confirmation."
    public init() {}
}

public struct QuoteLine: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: LineCategory
    public var source: EvidenceSource
    public var sourceDetail: String
    public var quantity: Decimal?
    public var unit: String
    public var specification: String
    public var confirmationPrompt: String?
    public var isReviewed: Bool
    public var rateID: UUID?
    /// Frozen only after contractor presses Approve pricing.
    public var approvedUnitPrice: Decimal?

    public init(
        id: UUID = UUID(), title: String, category: LineCategory,
        source: EvidenceSource, sourceDetail: String = "",
        quantity: Decimal? = nil, unit: String = "each",
        specification: String = "", confirmationPrompt: String? = nil,
        isReviewed: Bool = false, rateID: UUID? = nil, approvedUnitPrice: Decimal? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.source = source
        self.sourceDetail = sourceDetail
        self.quantity = quantity
        self.unit = unit
        self.specification = specification
        self.confirmationPrompt = confirmationPrompt
        self.isReviewed = isReviewed
        self.rateID = rateID
        self.approvedUnitPrice = approvedUnitPrice
    }
}

public struct Quote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var number: String
    public var title: String
    public var customerID: UUID?
    public var notes: String
    public var photoNames: [String]
    public var lines: [QuoteLine]
    public var createdAt: Date
    public var reviewApprovedAt: Date?
    public var pricingApprovedAt: Date?
    public var finalizedAt: Date?
    public var approvedVATPercent: Decimal?
    public var approvedCurrencyCode: String?
    public var status: QuoteStatus
    public var sentAt: Date?
    public var responseRecordedAt: Date?

    public init(id: UUID = UUID(), number: String, title: String = "New quotation", customerID: UUID? = nil, notes: String = "", photoNames: [String] = [], lines: [QuoteLine] = [], createdAt: Date = Date(), reviewApprovedAt: Date? = nil, pricingApprovedAt: Date? = nil, finalizedAt: Date? = nil, approvedVATPercent: Decimal? = nil, approvedCurrencyCode: String? = nil, status: QuoteStatus = .draft, sentAt: Date? = nil, responseRecordedAt: Date? = nil) {
        self.id = id
        self.number = number
        self.title = title
        self.customerID = customerID
        self.notes = notes
        self.photoNames = photoNames
        self.lines = lines
        self.createdAt = createdAt
        self.reviewApprovedAt = reviewApprovedAt
        self.pricingApprovedAt = pricingApprovedAt
        self.finalizedAt = finalizedAt
        self.approvedVATPercent = approvedVATPercent
        self.approvedCurrencyCode = approvedCurrencyCode
        self.status = status
        self.sentAt = sentAt
        self.responseRecordedAt = responseRecordedAt
    }

    /// Any scope or price selection edit invalidates previously recorded approvals.
    public mutating func invalidateApprovals() {
        reviewApprovedAt = nil
        pricingApprovedAt = nil
        approvedVATPercent = nil
        approvedCurrencyCode = nil
        for index in lines.indices { lines[index].approvedUnitPrice = nil }
        finalizedAt = nil
        status = .draft
        sentAt = nil
        responseRecordedAt = nil
    }
}

public struct AppSnapshot: Codable, Sendable {
    public var quotes: [Quote] = []
    public var customers: [Customer] = []
    public var rates: [Rate] = []
    public var business: BusinessProfile = BusinessProfile()
    public init() {}
}

public enum QuoteProblem: String, Equatable, Sendable {
    case noLines = "Add at least one item."
    case unconfirmedItem = "Confirm every item and quantity."
    case missingSpecification = "Complete the missing specifications flagged by AI."
    case missingRate = "Select a saved rate with a price for every line."
    case reviewNotApproved = "Approve the reviewed scope first."
    case pricingNotApproved = "Approve the pricing first."
    case missingBusiness = "Set business name and address in Settings."
    case missingCustomer = "Choose a customer with a name."
    case missingVAT = "Set a VAT percentage (including 0% if applicable)."
}
