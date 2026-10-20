import Foundation
import Observation
import UIKit
import QuoteCore

@MainActor @Observable
final class TradeQuoteStore {
    private(set) var snapshot: AppSnapshot
    var failureMessage: String?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    var quotes: [Quote] { snapshot.quotes.sorted { $0.createdAt > $1.createdAt } }
    var rates: [Rate] { snapshot.rates }
    var customers: [Customer] { snapshot.customers }
    var business: BusinessProfile { snapshot.business }

    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var jsonURL: URL { docs.appendingPathComponent("tradequote.json") }

    init() {
        var startupProblem: String?
        if let data = try? Data(contentsOf: Self.jsonURL),
           let restored = try? JSONDecoder().decode(AppSnapshot.self, from: data) {
            snapshot = restored
        } else {
            // Never silently overwrite a file we could not read; keep it aside for recovery.
            if FileManager.default.fileExists(atPath: Self.jsonURL.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = Self.docs.appendingPathComponent("tradequote-unreadable-\(stamp).json")
                try? FileManager.default.moveItem(at: Self.jsonURL, to: backup)
                startupProblem = "Saved data could not be read. A copy was kept as \(backup.lastPathComponent)."
            }
            var fresh = AppSnapshot()
            fresh.rates = [
                Rate(name: "Electrician (per hour)", category: .labour, unit: "h"),
                Rate(name: "Replace socket (labour)", category: .labour, unit: "each"),
                Rate(name: "Install light fitting (labour)", category: .labour, unit: "each"),
                Rate(name: "Double socket (13A)", category: .materials, unit: "each"),
                Rate(name: "LED ceiling light", category: .materials, unit: "each")
            ]
            snapshot = fresh
        }
        failureMessage = startupProblem
    }

    func quote(_ id: UUID) -> Quote? { snapshot.quotes.first { $0.id == id } }
    func customer(_ id: UUID?) -> Customer? { snapshot.customers.first { $0.id == id } }

    @discardableResult func newQuote() -> UUID {
        let year = Calendar.current.component(.year, from: .now)
        let prefix = "QT-\(year)-"
        let highest = snapshot.quotes.compactMap { quote -> Int? in
            guard quote.number.hasPrefix(prefix) else { return nil }
            return Int(quote.number.dropFirst(prefix.count))
        }.max() ?? 0
        let new = Quote(number: prefix + String(format: "%04d", highest + 1))
        snapshot.quotes.insert(new, at: 0)
        persist()
        return new.id
    }

    func editQuote(_ id: UUID, scopeChanged: Bool = false, _ change: (inout Quote) -> Void) {
        guard let index = snapshot.quotes.firstIndex(where: { $0.id == id }),
              snapshot.quotes[index].status == .draft else { return }
        if scopeChanged { snapshot.quotes[index].invalidateApprovals() }
        change(&snapshot.quotes[index])
        persist()
    }

    func review(_ id: UUID) {
        editQuote(id) { q in
            if QuoteRules.reviewProblems(q).isEmpty { q.reviewApprovedAt = Date() }
        }
    }

    @discardableResult func approvePricing(_ id: UUID) -> Bool {
        guard let quote = quote(id), quote.status == .draft else { return false }
        var q = quote
        guard QuoteRules.approvePricing(&q, rates: rates, business: business) else { return false }
        editQuote(id) { $0 = q }
        return true
    }

    func updateCustomer(_ customer: Customer) {
        if let index = snapshot.customers.firstIndex(where: { $0.id == customer.id }) {
            snapshot.customers[index] = customer
        } else {
            snapshot.customers.append(customer)
        }
        persist()
    }

    func updateRate(_ rate: Rate) {
        if let index = snapshot.rates.firstIndex(where: { $0.id == rate.id }) {
            snapshot.rates[index] = rate
        } else {
            snapshot.rates.append(rate)
        }
        persist()
    }

    func updateBusiness(_ profile: BusinessProfile) {
        snapshot.business = profile
        persist()
    }

    func deleteRate(_ id: UUID) {
        snapshot.rates.removeAll { $0.id == id }
        // Draft lines that pointed at this rate must be re-priced; approved prices stay frozen.
        for index in snapshot.quotes.indices where snapshot.quotes[index].status == .draft {
            for line in snapshot.quotes[index].lines.indices where snapshot.quotes[index].lines[line].rateID == id {
                snapshot.quotes[index].lines[line].rateID = nil
            }
        }
        persist()
    }

    func canDeleteCustomer(_ id: UUID) -> Bool {
        !snapshot.quotes.contains { $0.customerID == id }
    }

    func deleteCustomer(_ id: UUID) {
        guard canDeleteCustomer(id) else { return }
        snapshot.customers.removeAll { $0.id == id }
        persist()
    }

    func deleteQuote(_ id: UUID) {
        guard let quote = quote(id) else { return }
        snapshot.quotes.removeAll { $0.id == id }
        for name in quote.photoNames { deletePhotoFileIfUnused(name) }
        try? FileManager.default.removeItem(at: Self.pdfFolder.appendingPathComponent("\(id.uuidString).pdf"))
        persist()
    }

    func setStatus(_ status: QuoteStatus, for id: UUID) {
        guard let index = snapshot.quotes.firstIndex(where: { $0.id == id }),
              snapshot.quotes[index].finalizedAt != nil else { return }
        // Never pretend delivery or customer acceptance happened automatically.
        snapshot.quotes[index].status = status
        if status == .sent { snapshot.quotes[index].sentAt = .now }
        if status == .accepted || status == .declined { snapshot.quotes[index].responseRecordedAt = .now }
        persist()
    }

    func duplicate(_ id: UUID) -> UUID? {
        guard var original = quote(id) else { return nil }
        let newID = newQuote()
        guard let index = snapshot.quotes.firstIndex(where: { $0.id == newID }) else { return nil }
        let number = snapshot.quotes[index].number
        original.id = newID
        original.number = number
        original.createdAt = Date()
        original.invalidateApprovals()
        original.lines = original.lines.map { line in
            var line = line
            line.id = UUID()
            line.isReviewed = false
            return line
        }
        snapshot.quotes[index] = original
        persist()
        return newID
    }

    func photoURL(named filename: String) -> URL {
        Self.docs.appendingPathComponent("Photos", isDirectory: true).appendingPathComponent(filename)
    }

    func photo(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: photoURL(named: filename).path)
    }

    func addPhoto(_ image: UIImage, to quoteID: UUID) throws {
        let directory = Self.docs.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).jpg"
        // Bound size and strip original metadata before local persistence and model prompting.
        let targetWidth: CGFloat = min(1600, image.size.width)
        let ratio = image.size.width > 0 ? targetWidth / image.size.width : 1
        let size = CGSize(width: targetWidth, height: image.size.height * ratio)
        let normalized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let bytes = normalized.jpegData(compressionQuality: 0.82) else {
            throw StorageError.imageEncodeFailed
        }
        try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
        editQuote(quoteID, scopeChanged: true) { $0.photoNames.append(name) }
    }

    func removePhoto(_ filename: String, from id: UUID) {
        guard quote(id)?.photoNames.contains(filename) == true else { return }
        editQuote(id, scopeChanged: true) { $0.photoNames.removeAll { $0 == filename } }
        deletePhotoFileIfUnused(filename)
    }

    /// Duplicated quotes share photo files, so only delete a file nobody references.
    private func deletePhotoFileIfUnused(_ filename: String) {
        guard !snapshot.quotes.contains(where: { $0.photoNames.contains(filename) }) else { return }
        try? FileManager.default.removeItem(at: photoURL(named: filename))
    }

    func saveFinalPDF(_ id: UUID) throws -> URL {
        guard var quote = quote(id) else { throw StorageError.missingQuote }
        guard quote.finalizedAt == nil, quote.status == .draft else {
            if let existing = pdfURL(id) { return existing }
            throw StorageError.notApproved("This quotation has already been finalized.")
        }
        let problems = QuoteRules.finalizationProblems(quote, rates: rates, business: business, customers: customers)
        guard problems.isEmpty, let customer = customer(quote.customerID) else {
            throw StorageError.notApproved(problems.map(\.rawValue).joined(separator: " "))
        }
        let bytes = try QuotePDF.generate(quote: quote, business: business, customer: customer, rates: rates)
        let folder = Self.pdfFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(quote.id.uuidString).pdf")
        try bytes.write(to: url, options: .atomic)
        quote.finalizedAt = .now
        quote.status = .final
        editQuote(id) { $0 = quote }
        return url
    }

    private static var pdfFolder: URL { docs.appendingPathComponent("PDFs", isDirectory: true) }

    func pdfURL(_ id: UUID) -> URL? {
        guard quote(id)?.finalizedAt != nil else { return nil }
        let url = Self.pdfFolder.appendingPathComponent("\(id.uuidString).pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A copy of the final PDF named after the quote number, so the customer doesn't receive "<UUID>.pdf".
    func shareablePDF(_ id: UUID) -> URL? {
        guard let source = pdfURL(id), let quote = quote(id) else { return nil }
        let safeName = quote.number.replacingOccurrences(of: "/", with: "-")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
        let target = folder.appendingPathComponent("\(safeName).pdf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            return source
        }
    }

    /// Coalesces rapid edits (e.g. typing) into one disk write shortly afterwards.
    private func persist() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes immediately. Called when the app goes to the background.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: Self.jsonURL, options: .atomic)
            if failureMessage != nil { failureMessage = nil }
        } catch {
            let message = "Saving your data failed: \(error.localizedDescription)"
            if failureMessage != message { failureMessage = message }
        }
    }

    enum StorageError: LocalizedError {
        case missingQuote, imageEncodeFailed, notApproved(String)
        var errorDescription: String? {
            switch self {
            case .missingQuote: return "Quote could not be found."
            case .imageEncodeFailed: return "Photo could not be stored."
            case .notApproved(let text): return text
            }
        }
    }
}
