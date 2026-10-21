import Foundation

public enum LineCategory: String, Codable, CaseIterable, Sendable {
    case labour = "Labour"
    case materials = "Materials"
}

public enum EvidenceSource: String, Codable, Sendable {
    case voice = "Voice"
    case photo = "Photo"
    case manual = "Manual"
    case note = "Typed note"
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
    public var aliases: [String]? = nil
    public var productCode: String? = nil
    public var purchaseCost: Decimal? = nil
    public var updatedAt: Date? = nil
    public var isFavourite: Bool? = nil

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
    public var recipeID: UUID? = nil
    public var room: String? = nil
    public var sourceStart: Int? = nil
    public var sourceLength: Int? = nil
    public var isApproximate: Bool? = nil
    public var disposition: ScopeDisposition? = nil
    public var optionalSelected: Bool? = nil
    public var supply: MaterialSupply? = nil
    public var confirmationKind: ConfirmationKind? = nil
    public var workActionRequired: Bool? = nil
    public var capturedWorkObject: String? = nil
    public var linkedPhotos: [String]? = nil
    public var needsRateMatch: Bool? = nil
    public var isRecipeContainer: Bool? = nil

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
    public var materialsConfirmed: Bool
    public var pricingApprovedAt: Date?
    public var finalizedAt: Date?
    public var approvedVATPercent: Decimal?
    public var approvedCurrencyCode: String?
    public var status: QuoteStatus
    public var sentAt: Date?
    public var responseRecordedAt: Date?
    // Optional additions preserve decoding of quotations from version 1.0.
    public var workflowVersion: Int? = nil
    public var billingMethod: LabourBilling? = nil
    public var fixedLabourPrice: Decimal? = nil
    public var observations: [PhotoObservation]? = nil
    public var voiceTranscripts: [String]? = nil
    public var photoContexts: [PhotoContext]? = nil
    public var versions: [QuoteVersion]? = nil
    public var revisionOf: String? = nil
    public var expiresAt: Date? = nil
    public var followUpAt: Date? = nil
    public var depositPercent: Decimal? = nil
    public var paymentSchedule: String? = nil
    public var approvedTerms: String? = nil
    public var approvedBusiness: BusinessProfile? = nil
    public var approvedCustomer: Customer? = nil

    public init(id: UUID = UUID(), number: String, title: String = "New quotation", customerID: UUID? = nil, notes: String = "", photoNames: [String] = [], lines: [QuoteLine] = [], createdAt: Date = Date(), reviewApprovedAt: Date? = nil, materialsConfirmed: Bool = false, pricingApprovedAt: Date? = nil, finalizedAt: Date? = nil, approvedVATPercent: Decimal? = nil, approvedCurrencyCode: String? = nil, status: QuoteStatus = .draft, sentAt: Date? = nil, responseRecordedAt: Date? = nil) {
        self.id = id
        self.number = number
        self.title = title
        self.customerID = customerID
        self.notes = notes
        self.photoNames = photoNames
        self.lines = lines
        self.createdAt = createdAt
        self.reviewApprovedAt = reviewApprovedAt
        self.materialsConfirmed = materialsConfirmed
        self.pricingApprovedAt = pricingApprovedAt
        self.finalizedAt = finalizedAt
        self.approvedVATPercent = approvedVATPercent
        self.approvedCurrencyCode = approvedCurrencyCode
        self.status = status
        self.sentAt = sentAt
        self.responseRecordedAt = responseRecordedAt
    }

    /// Price changes leave the contractor's scope and materials checks intact.
    public mutating func invalidatePricingApproval() {
        pricingApprovedAt = nil
        approvedVATPercent = nil
        approvedCurrencyCode = nil
        approvedTerms = nil
        approvedBusiness = nil
        approvedCustomer = nil
        for index in lines.indices { lines[index].approvedUnitPrice = nil }
        finalizedAt = nil
        status = .draft
        sentAt = nil
        responseRecordedAt = nil
    }
    public mutating func invalidateApprovals() {
        reviewApprovedAt = nil
        materialsConfirmed = false
        invalidatePricingApproval()
    }
}

public struct AppSnapshot: Codable, Sendable {
    public var quotes: [Quote] = []
    public var customers: [Customer] = []
    public var rates: [Rate] = []
    public var business: BusinessProfile = BusinessProfile()
    public var recipes: [JobRecipe]? = nil
    public init() {}
}

public enum QuoteProblem: String, Equatable, Sendable {
    case noLines = "Add at least one item."
    case unconfirmedItem = "Confirm every item and quantity."
    case materialsNotReviewed = "Check the materials needed (including none) before approving."
    case missingRate = "Select a saved rate with a price for every line."
    case reviewNotApproved = "Approve the reviewed scope first."
    case pricingNotApproved = "Approve the pricing first."
    case missingBusiness = "Set business name and address in Settings."
    case missingCustomer = "Choose a customer with a name."
    case billingOverlap = "Choose hourly, per-task or fixed labour pricing to avoid overlapping labour charges."
    case missingHours = "Add the whole-job labour hours before approving hourly pricing."
    case missingTaskRate = "Per-task pricing needs at least one included labour task, not only an hour allowance."
    case missingFixedPrice = "Set the agreed fixed labour price."
    case supplyNotConfirmed = "Confirm who supplies materials for each job recipe."
    case invalidCommercialTerms = "Check deposit (0–100%), expiry and payment details."
    case noIncludedWork = "Include at least one work item in the quotation."
    case missingVAT = "Set a VAT percentage (including 0% if applicable)."
}

