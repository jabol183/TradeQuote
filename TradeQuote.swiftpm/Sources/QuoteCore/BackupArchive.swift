import Foundation

public struct BackupArchive: Codable, Sendable {
    public var formatVersion: Int = 1
    public var createdAt = Date()
    public var snapshot: AppSnapshot
    public var photos: [String: Data]
    public var pdfs: [String: Data]
    public init(snapshot: AppSnapshot, photos: [String: Data], pdfs: [String: Data]) {
        self.snapshot = snapshot; self.photos = photos; self.pdfs = pdfs
    }
    public func validate() throws {
        guard formatVersion == 1 else { throw Failure.invalid("Unsupported backup version.") }
        guard Set(snapshot.quotes.map(\.id)).count == snapshot.quotes.count,
              Set(snapshot.customers.map(\.id)).count == snapshot.customers.count,
              Set(snapshot.rates.map(\.id)).count == snapshot.rates.count else { throw Failure.invalid("Duplicate record IDs in backup.") }
        for name in photos.keys {
            guard name.range(of: "^[A-Fa-f0-9-]{36}\\.jpg$", options: .regularExpression) != nil,
                  UUID(uuidString: String(name.dropLast(4))) != nil else { throw Failure.invalid("Invalid photo name in backup.") }
        }
        for name in pdfs.keys {
            guard name.range(of: "^[A-Fa-f0-9-]{36}\\.pdf$", options: .regularExpression) != nil,
                  UUID(uuidString: String(name.dropLast(4))) != nil,
                  pdfs[name]?.starts(with: Data("%PDF-".utf8)) == true else { throw Failure.invalid("Invalid PDF in backup.") }
        }
        for quote in snapshot.quotes {
            guard Set(quote.lines.map(\.id)).count == quote.lines.count,
                  quote.photoNames.allSatisfy({ photos[$0] != nil }) else { throw Failure.invalid("Missing photos or duplicate quote items in backup.") }
            if quote.finalizedAt != nil && pdfs[quote.id.uuidString + ".pdf"] == nil { throw Failure.invalid("A final quotation is missing its PDF.") }
            guard quote.lines.allSatisfy({ ($0.linkedPhotos ?? []).allSatisfy(quote.photoNames.contains) }) else { throw Failure.invalid("A work item refers to an unavailable photo.") }
        }
    }
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
}
