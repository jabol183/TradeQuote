import SwiftUI
import QuoteCore

struct EvaluationView: View {
    @Environment(TradeQuoteStore.self) private var store
    @State private var running = false
    @State private var results: [String: String] = [:]
    @State private var task: Task<Void, Never>?
    var body: some View {
        List {
            Section {
                Text("Runs ten fixed sample notes through the existing on-device model. No customer records are used or changed. Quantity checks are a diagnostic; inspect scope, supply and exclusions yourself.").font(.subheadline)
                Button(running ? "Running…" : "Run on this device") {
                    running = true; results = [:]
                    task = Task { @MainActor in
                        defer { running = false }
                        for example in ExtractionExample.cases {
                            if Task.isCancelled { return }
                            let started = Date()
                            do {
                                let result = try await DraftAI.extractVoice(example.note, source: .note, recipes: store.recipes, existing: [])
                                let quantities = result.changes.compactMap { $0.line.quantity }.sorted()
                                let expected = example.quantities.sorted()
                                let summary = result.changes.map { "\($0.line.title): \($0.line.quantity?.editable ?? "?") \($0.line.unit), \($0.line.disposition?.rawValue ?? "Included"), supply \($0.line.supply?.rawValue ?? "unknown")" }.joined(separator: "\n")
                                let match = quantities == expected
                                results[example.id] = "\(match ? "Quantity check passed" : "Quantity mismatch — inspect output") · \(String(format: "%.1f", Date().timeIntervalSince(started)))s\n\(summary)\n\(result.warnings.joined(separator: "\n"))"
                            } catch { results[example.id] = error.localizedDescription }
                        }
                    }
                }.disabled(running)
            }
            ForEach(ExtractionExample.cases) { example in
                Section(example.id) {
                    Text(example.note).font(.subheadline)
                    Text(results[example.id] ?? "Not run").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Extraction checks")
        .onDisappear { task?.cancel() }
    }
}
