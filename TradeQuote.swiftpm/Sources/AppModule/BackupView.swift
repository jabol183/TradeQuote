import SwiftUI
import UniformTypeIdentifiers
import QuoteCore

struct BackupView: View {
    @Environment(TradeQuoteStore.self) private var store
    @State private var exported: URL?
    @State private var importing = false
    @State private var pending: BackupArchive?
    @State private var message: String?
    var body: some View {
        Section("Backup and restore") {
            Text("A full backup includes customers, rates, recipes, quotes, source photos and final PDFs. Save it in Files. The backup contains customer information and is not encrypted.").font(.caption)
            Button("Prepare full backup") {
                do { exported = try store.exportBackup(); message = nil } catch { message = error.localizedDescription }
            }
            if let exported { ShareLink("Save / share backup", item: exported) }
            Button("Restore from backup") { importing = true }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 250_000_000 else { throw BackupArchive.Failure.invalid("This backup is larger than the 250 MB restore limit.") }
                let archive = try JSONDecoder().decode(BackupArchive.self, from: Data(contentsOf: url))
                try archive.validate(); pending = archive
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Replace this device's TradeQuote data?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Restore backup and replace local data", role: .destructive) {
                do { if let pending { try store.restoreBackup(pending) }; message = "Backup restored." }
                catch { message = error.localizedDescription }
                pending = nil
            }
        } message: {
            if let pending { Text("Backup contains \(pending.snapshot.quotes.count) quotes and \(pending.photos.count) photos, saved \(pending.createdAt.formatted()). Export your current data first if you want to keep it.") }
        }
    }
}
