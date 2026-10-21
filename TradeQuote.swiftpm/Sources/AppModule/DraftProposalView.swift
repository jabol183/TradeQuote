import SwiftUI
import UIKit
import QuoteCore

struct DraftProposal: Identifiable {
    let id = UUID()
    var changes: [DraftChange]
    var observations: [PhotoObservation]
    var warnings: [String]
}
struct DraftProposalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TradeQuoteStore.self) private var store
    let proposal: DraftProposal
    let quoteID: UUID
    let apply: ([DraftChange], [PhotoObservation]) -> Void
    @State private var selected = Set<UUID>()
    @State private var observed = Set<UUID>()
    @State private var conflictTargets: [UUID: UUID] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the changes to apply. Quantities are highlighted for checking. Nothing is approved or priced by AI.")
                    ForEach(proposal.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                }
                ForEach(proposal.changes) { change in
                    Section(change.operation == .conflict ? "Resolve possible duplicate" : change.operation.rawValue.capitalized) {
                        Toggle(isOn: Binding(get: { selected.contains(change.id) }, set: { value in
                            if value { selected.insert(change.id) } else { selected.remove(change.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(change.line.title).font(.headline)
                                Text(change.explanation).font(.subheadline)
                                if change.operation != .remove {
                                    Text("\(change.line.isApproximate == true ? "Approximately " : "")\(change.line.quantity?.editable ?? "Quantity missing") \(change.line.unit)")
                                        .font(.headline).foregroundStyle(.orange)
                                    if let room = change.line.room { Text(room).font(.caption) }
                                }
                                Text(change.line.sourceDetail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if change.operation == .conflict {
                            Picker("Apply to", selection: Binding<UUID?>(get: { conflictTargets[change.id] }, set: { conflictTargets[change.id] = $0 })) {
                                Text("Add as separate work (check location)").tag(nil as UUID?)
                                ForEach(store.quote(quoteID)?.lines ?? []) { line in
                                    Text("Update: \(line.title) · \(line.room ?? "no room")").tag(Optional(line.id))
                                }
                            }
                        }
                    }
                }
                if !proposal.observations.isEmpty {
                    Section("Photo observations — evidence only") {
                        ForEach(proposal.observations) { observation in
                            Toggle(isOn: Binding(get: { observed.contains(observation.id) }, set: { flag in
                                if flag { observed.insert(observation.id) } else { observed.remove(observation.id) }
                            })) {
                                HStack {
                                    PhotoThumb(filename: observation.filename).scaleEffect(0.7).frame(width: 64, height: 64)
                                    Text(observation.text).font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Proposed changes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply selected") {
                        let changes = proposal.changes.filter { selected.contains($0.id) }.map { original in
                            var change = original
                            if change.operation == .conflict {
                                change.existingID = conflictTargets[change.id]
                                change.operation = change.existingID == nil ? .add : .update
                                if let id = change.existingID { change.line.id = id }
                            }
                            return change
                        }
                        apply(changes, proposal.observations.filter { observed.contains($0.id) })
                    }.disabled(selected.isEmpty && observed.isEmpty)
                }
            }
            .onAppear {
                selected = Set(proposal.changes.filter { $0.operation != .conflict && $0.operation != .remove }.map(\.id))
                observed = Set(proposal.observations.map(\.id))
            }
        }
    }
}

struct PhotoEvidenceEditor: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var context: PhotoContext
    let quoteID: UUID
    @State private var crop: UIImage?
    @State private var cropError: String?
    var body: some View {
        NavigationStack {
            Form {
                if let image = crop ?? store.photo(named: context.filename) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                }
                Section("Guide the photo analysis") {
                    Picker("Purpose", selection: $context.purpose) { ForEach(PhotoPurpose.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("What should the app focus on?", text: $context.instruction, axis: .vertical)
                    Picker("Link to work item", selection: $context.lineID) {
                        Text("Whole job").tag(nil as UUID?)
                        ForEach(store.quote(quoteID)?.lines ?? []) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Text("Photographs produce observations. Only your confirmed instructions become quoted work.").font(.caption)
                }
                Section("Focus on the centre of the photo") {
                    Button("Crop centre (keep original evidence)") {
                        guard let original = crop ?? store.photo(named: context.filename), let cg = original.cgImage else { return }
                        let w = CGFloat(cg.width), h = CGFloat(cg.height)
                        let rect = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7).integral
                        if let result = cg.cropping(to: rect) { crop = UIImage(cgImage: result) }
                    }
                    if crop != nil { Button("Reset crop") { crop = nil } }
                    Text("Move the object into the centre when taking the photo; cropping creates an additional detail photo.").font(.caption)
                    if let cropError { Text(cropError).foregroundStyle(.red) }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Photo evidence")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            if let crop {
                                let before = Set(store.quote(quoteID)?.photoNames ?? [])
                                try store.addPhoto(crop, to: quoteID)
                                if let name = store.quote(quoteID)?.photoNames.first(where: { !before.contains($0) }) { context.filename = name }
                            }
                            let saved = context
                            store.editQuote(quoteID, scopeChanged: true) { quote in
                                var contexts = quote.photoContexts ?? []
                                contexts.removeAll { $0.filename == saved.filename }
                                contexts.append(saved); quote.photoContexts = contexts
                                if let index = quote.lines.firstIndex(where: { $0.id == saved.lineID }) {
                                    quote.lines[index].linkedPhotos = Array(Set((quote.lines[index].linkedPhotos ?? []) + [saved.filename]))
                                }
                            }
                            dismiss()
                        } catch { cropError = error.localizedDescription }
                    }
                }
            }
        }
    }
}
