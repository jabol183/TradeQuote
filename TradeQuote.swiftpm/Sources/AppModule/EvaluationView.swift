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
                Text("Runs ten fixed notes through the production extraction path. Checks item count, quantities, units, rooms, supply, optionality, exclusions and approximate hours. Apple catalogue matching is used only when needed. Customer records are unchanged.").font(.subheadline)
                Button(running ? "Running…" : "Run on this device") {
                    running = true; results = [:]
                    task = Task { @MainActor in
                        defer { running = false }
                        for example in ExtractionExample.cases {
                            if Task.isCancelled { return }
                            let started = Date()
                            do {
                                let result = try await DraftAI.extractVoice(example.note, source: .note, recipes: store.recipes, existing: [])
                                let failures = ExtractionChecks.problems(result.changes.map(\.line), expected: example.expected)
                                let summary = result.changes.map { "\($0.line.title): \($0.line.quantity?.editable ?? "?") \($0.line.unit), \($0.line.disposition?.rawValue ?? "Included"), supply \($0.line.supply?.rawValue ?? "unknown"), room \($0.line.room ?? "—"), approximate \($0.line.isApproximate == true ? "yes" : "no")" }.joined(separator: "\n")
                                results[example.id] = "\(failures.isEmpty ? "All fact checks passed" : "FAILED: " + failures.joined(separator: " ")) · \(String(format: "%.1f", Date().timeIntervalSince(started)))s\n\(summary)\n\(result.warnings.joined(separator: "\n"))"
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
