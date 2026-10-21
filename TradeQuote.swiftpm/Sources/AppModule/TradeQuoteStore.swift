import Foundation
import Observation
import UIKit
import QuoteCore
import UserNotifications

@MainActor @Observable
final class TradeQuoteStore {
    private(set) var snapshot: AppSnapshot
    var failureMessage: String?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    var quotes: [Quote] { snapshot.quotes.sorted { $0.createdAt > $1.createdAt } }
    var rates: [Rate] { snapshot.rates }
    var customers: [Customer] { snapshot.customers }
    var business: BusinessProfile { snapshot.business }
    var recipes: [JobRecipe] { snapshot.recipes ?? JobRecipe.starters }

    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var jsonURL: URL { docs.appendingPathComponent("tradequote.json") }

    init() {
        var startupProblem: String?
        if let data = try? Data(contentsOf: Self.jsonURL),
           let restored = try? JSONDecoder().decode(AppSnapshot.self, from: data) {
            var cleaned = restored
            // Earlier builds stored the model's "None" as a confirmation question; drop it from drafts.
            for q in cleaned.quotes.indices where cleaned.quotes[q].status == .draft {
                cleaned.quotes[q].lines = cleaned.quotes[q].lines.map { line in
                    line.source == .manual ? line : QuoteRules.cleanedAIPlaceholders(line)
                }
            }
            snapshot = cleaned
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
        if snapshot.recipes == nil { snapshot.recipes = JobRecipe.starters }
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
        var new = Quote(number: prefix + String(format: "%04d", highest + 1))
        new.workflowVersion = 2
        new.expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: .now)
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
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
        if status == .accepted || status == .declined {
            snapshot.quotes[index].responseRecordedAt = .now
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        }
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
        original.revisionOf = quote(id)?.number
        original.versions = []
        original.approvedBusiness = nil
        original.approvedCustomer = nil
        original.approvedTerms = nil
        original.expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: .now)
        original.followUpAt = nil
        let lineIDs = Dictionary(uniqueKeysWithValues: original.lines.map { ($0.id, UUID()) })
        original.photoContexts = original.photoContexts?.map { context in
            var context = context
            context.lineID = context.lineID.flatMap { lineIDs[$0] }
            return context
        }
        original.observations = original.observations?.map { observation in
            var observation = observation
            observation.promotedLineID = observation.promotedLineID.flatMap { lineIDs[$0] }
            return observation
        }
        original.lines = original.lines.map { line in
            var line = line
            line.id = lineIDs[line.id] ?? UUID()
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
        editQuote(id, scopeChanged: true) { quote in
            quote.photoNames.removeAll { $0 == filename }
            quote.photoContexts?.removeAll { $0.filename == filename }
            quote.observations?.removeAll { $0.filename == filename }
            for index in quote.lines.indices { quote.lines[index].linkedPhotos?.removeAll { $0 == filename } }
        }
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
        quote.approvedBusiness = business
        quote.approvedCustomer = customer
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

    func updateRecipe(_ recipe: JobRecipe) {
        var all = recipes
        if let index = all.firstIndex(where: { $0.id == recipe.id }) { all[index] = recipe }
        else { all.append(recipe) }
        snapshot.recipes = all
        persist()
    }

    func saveLine(_ line: QuoteLine, in id: UUID) {
        checkpoint(id, reason: "Before editing \(line.title)")
        editQuote(id, scopeChanged: true) { quote in
            if let index = quote.lines.firstIndex(where: { $0.id == line.id }) { quote.lines[index] = line }
            else { quote.lines.append(line) }
        }
    }

    func checkpoint(_ id: UUID, reason: String) {
        editQuote(id) { quote in
            var versions = quote.versions ?? []
            versions.append(QuoteVersion(reason: reason, lines: quote.lines, observations: quote.observations ?? []))
            quote.versions = Array(versions.suffix(25))
        }
    }

    func restoreVersion(_ version: QuoteVersion, in id: UUID) {
        checkpoint(id, reason: "Before restoring version")
        editQuote(id, scopeChanged: true) { quote in
            let validPhotos = Set(quote.photoNames)
            quote.lines = version.lines.map { item in
                var line = item
                line.isReviewed = false
                line.approvedUnitPrice = nil
                line.linkedPhotos = line.linkedPhotos?.filter { validPhotos.contains($0) }
                return line
            }
            quote.observations = version.observations.filter { validPhotos.contains($0.filename) }
        }
    }

    func apply(_ changes: [DraftChange], observations: [PhotoObservation], to id: UUID) {
        guard !changes.isEmpty || !observations.isEmpty else { return }
        checkpoint(id, reason: "Before applying AI suggestions")
        editQuote(id, scopeChanged: true) { quote in
            for change in changes where change.operation != .conflict {
                switch change.operation {
                case .remove:
                    quote.lines.removeAll { $0.id == change.existingID }
                    quote.observations = quote.observations?.map { observation in
                        var observation = observation
                        if observation.promotedLineID == change.existingID { observation.promotedLineID = nil }
                        return observation
                    }
                case .update:
                    if let index = quote.lines.firstIndex(where: { $0.id == change.existingID }) {
                        var line = change.line
                        line.isReviewed = false; line.approvedUnitPrice = nil
                        quote.lines[index] = line
                    }
                case .add:
                    var line = change.line
                    line.isReviewed = false; line.approvedUnitPrice = nil
                    quote.lines.append(line)
                case .conflict: break
                }
            }
            var all = quote.observations ?? []
            for item in observations where !all.contains(where: { $0.filename == item.filename && $0.text == item.text }) { all.append(item) }
            quote.observations = all
        }
    }

    func expandRecipe(for lineID: UUID, in id: UUID) {
        guard let quote = quote(id), let parent = quote.lines.first(where: { $0.id == lineID }),
              let recipe = recipes.first(where: { $0.id == parent.recipeID }), let quantity = parent.quantity else { return }
        checkpoint(id, reason: "Before adding configured recipe components")
        editQuote(id, scopeChanged: true) { quote in
            for component in recipe.components {
                if component.category == .materials && parent.supply != .contractor { continue }
                let witness = "Recipe \(recipe.name), configured by contractor; parent \(parent.id.uuidString)"
                guard !quote.lines.contains(where: { $0.sourceDetail == witness && $0.title == component.title }) else { continue }
                var line = QuoteLine(title: component.title, category: component.category, source: .manual,
                    sourceDetail: witness, quantity: component.quantityPerJob * quantity, unit: component.unit)
                line.rateID = component.rateID; line.supply = parent.supply; line.room = parent.room
                quote.lines.append(line)
            }
            // The recipe parent becomes descriptive scope; component labour is priced separately.
            if let index = quote.lines.firstIndex(where: { $0.id == parent.id }) { quote.lines[index].isRecipeContainer = true }
        }
    }

    func importRates(_ imported: [Rate]) {
        for rate in imported {
            var rate = rate
            if let old = snapshot.rates.first(where: {
                WorkflowRules.normalized($0.name) == WorkflowRules.normalized(rate.name) &&
                $0.category == rate.category && QuoteRules.unitsMatch($0.unit, rate.unit)
            }) { rate.id = old.id }
            updateRate(rate)
        }
    }

    func materialsList(_ id: UUID) throws -> URL {
        guard let quote = quote(id) else { throw StorageError.missingQuote }
        let rows = quote.lines.filter { $0.category == .materials && WorkflowRules.included($0) }.map {
            "\($0.quantity?.editable ?? "?") \($0.unit) — \($0.title) — \($0.specification) — supplied by \($0.supply?.rawValue ?? "Confirm")"
        }
        let data = "\(quote.number) — Materials\n" + (rows.isEmpty ? "No material lines recorded. Check the reviewed scope before purchasing." : rows.joined(separator: "\n"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(quote.number)-materials.txt")
        try data.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportBackup() throws -> URL {
        saveNow()
        var photos: [String: Data] = [:], pdfs: [String: Data] = [:]
        for quote in snapshot.quotes {
            for name in quote.photoNames { photos[name] = try Data(contentsOf: photoURL(named: name)) }
            if quote.finalizedAt != nil {
                let name = quote.id.uuidString + ".pdf"
                pdfs[name] = try Data(contentsOf: Self.pdfFolder.appendingPathComponent(name))
            }
        }
        let archive = BackupArchive(snapshot: snapshot, photos: photos, pdfs: pdfs)
        try archive.validate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TradeQuote-backup-\(Int(Date().timeIntervalSince1970)).json")
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
        return url
    }

    func restoreBackup(_ archive: BackupArchive) throws {
        try archive.validate()
        let fm = FileManager.default
        let staged = Self.docs.appendingPathComponent("Restore-\(UUID().uuidString)", isDirectory: true)
        let recovery = Self.docs.appendingPathComponent("Recovery-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staged.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staged.appendingPathComponent("PDFs"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staged) }
        for (name, data) in archive.photos { try data.write(to: staged.appendingPathComponent("Photos").appendingPathComponent(name), options: .atomic) }
        for (name, data) in archive.pdfs { try data.write(to: staged.appendingPathComponent("PDFs").appendingPathComponent(name), options: .atomic) }
        var restored = archive.snapshot
        if restored.recipes == nil { restored.recipes = JobRecipe.starters }
        try JSONEncoder().encode(restored).write(to: staged.appendingPathComponent("tradequote.json"), options: .atomic)
        pendingSave?.cancel(); pendingSave = nil
        try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
        var moved: [String] = [], installed: [String] = []
        do {
            for name in ["Photos", "PDFs", "tradequote.json"] {
                let current = Self.docs.appendingPathComponent(name)
                if fm.fileExists(atPath: current.path) { try fm.moveItem(at: current, to: recovery.appendingPathComponent(name)); moved.append(name) }
                try fm.moveItem(at: staged.appendingPathComponent(name), to: current); installed.append(name)
            }
        } catch {
            for name in installed { try? fm.removeItem(at: Self.docs.appendingPathComponent(name)) }
            for name in moved { try? fm.moveItem(at: recovery.appendingPathComponent(name), to: Self.docs.appendingPathComponent(name)) }
            throw error
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: snapshot.quotes.map { $0.id.uuidString })
        snapshot = restored
        failureMessage = nil
        try? fm.removeItem(at: recovery)
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

