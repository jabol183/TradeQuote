import SwiftUI
import QuoteCore

struct ReviewView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    var addEvidence: (() -> Void)? = nil
    let next: () -> Void
    @State private var editing: QuoteLine?
    @State private var addingCustomer = false
    @State private var recipes = false
    @State private var history = false
    @State private var selected = Set<UUID>()
    @State private var promoted: PhotoObservation?
    private var quote: Quote? { store.quote(quoteID) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Heading(text: "Review the job")
                Text("Confirm the requested work and highlighted quantities. Photos are evidence; your approval establishes scope.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let addEvidence { Button("Add photos or dictation", action: addEvidence) }
                if let quote {
                    TextField("Job title", text: Binding(get: { store.quote(quoteID)?.title ?? "" }, set: { value in store.editQuote(quoteID) { $0.title = value } }))
                        .font(.title3.bold()).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                    HStack {
                        Button { recipes = true } label: { Label("Add job recipe", systemImage: "square.stack.3d.up") }
                        Spacer()
                        Button { history = true } label: { Label("Undo / history", systemImage: "clock.arrow.circlepath") }
                    }.font(.subheadline)
                    LabourBillingPanel(quoteID: quoteID)
                    VStack(alignment: .leading, spacing: 8) {
                        Heading(text: "Customer")
                        Picker("Assign customer", selection: Binding(get: { store.quote(quoteID)?.customerID }, set: { id in store.editQuote(quoteID) { $0.customerID = id } })) {
                            Text("Select customer").tag(nil as UUID?)
                            ForEach(store.customers) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("Add customer") { addingCustomer = true }
                    }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                    ForEach(quote.lines) { line in
                        ReviewItemCard(quoteID: quoteID, lineID: line.id, selected: Binding(get: { selected.contains(line.id) }, set: { flag in
                            if flag { selected.insert(line.id) } else { selected.remove(line.id) }
                        }), edit: { editing = line })
                    }
                    if !selected.isEmpty {
                        Button("Confirm selected complete items (\(selected.count))") {
                            store.editQuote(quoteID, scopeChanged: true) { quote in
                                for i in quote.lines.indices where selected.contains(quote.lines[i].id) && WorkflowRules.canConfirm(quote.lines[i]) { quote.lines[i].isReviewed = true }
                            }
                            selected.removeAll()
                        }
                    }
                    Button { editing = QuoteLine(title: "", category: .labour, source: .manual, quantity: 1) } label: { Label("Add item manually", systemImage: "plus") }
                    if let observations = quote.observations, !observations.isEmpty {
                        Heading(text: "Photo observations")
                        ForEach(observations) { observation in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) { PhotoThumb(filename: observation.filename); Text(observation.text).font(.subheadline) }
                                if observation.promotedLineID == nil {
                                    Button("Create work item from this observation") {
                                        promoted = observation
                                        var line = QuoteLine(title: "", category: .labour, source: .photo, sourceDetail: observation.text,
                                            confirmationPrompt: "Describe the work you actually want to quote.")
                                        line.confirmationKind = .instruction; line.linkedPhotos = [observation.filename]
                                        editing = line
                                    }
                                } else { Label("Linked to work item", systemImage: "link").font(.caption) }
                            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                    Toggle("I checked all materials required, including customer supply", isOn: Binding(get: { store.quote(quoteID)?.materialsConfirmed ?? false }, set: { flag in store.editQuote(quoteID, scopeChanged: true) { $0.materialsConfirmed = flag } }))
                        .tint(Theme.blue)
                    ValidationMessages(messages: QuoteRules.reviewProblems(quote).map(\.rawValue))
                    ActionButton(title: "Approve scope & continue", icon: "checkmark.shield", disabled: !QuoteRules.reviewProblems(quote).isEmpty) {
                        store.review(quoteID); next()
                    }
                }
            }.padding(17)
        }
        .keyboardDoneButton().background(Theme.bg).navigationTitle("Review scope").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { promoted = nil }) { item in
            LineEditor(line: item, quoteID: quoteID, canDelete: quote?.lines.contains(where: { $0.id == item.id }) == true, onSave: { line in
                store.saveLine(line, in: quoteID)
                if let promoted {
                    store.editQuote(quoteID) { quote in
                        if let i = quote.observations?.firstIndex(where: { $0.id == promoted.id }) { quote.observations?[i].promotedLineID = line.id }
                    }
                }
                editing = nil
            }, onDelete: {
                store.checkpoint(quoteID, reason: "Before removing item")
                store.editQuote(quoteID, scopeChanged: true) { $0.lines.removeAll { $0.id == item.id } }; editing = nil
            })
        }
        .sheet(isPresented: $addingCustomer) { CustomerEditor(customer: Customer()) { store.updateCustomer($0) } }
        .sheet(isPresented: $recipes) { NavigationStack { RecipeLibraryView { store.saveLine($0.scopeLine(), in: quoteID) } } }
        .sheet(isPresented: $history) { VersionHistoryView(quoteID: quoteID) }
    }
}
struct ReviewItemCard: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    let lineID: UUID
    @Binding var selected: Bool
    var showsSelection = true
    let edit: () -> Void
    init(quoteID: UUID, lineID: UUID, selected: Binding<Bool>, showsSelection: Bool = true, edit: @escaping () -> Void) {
        self.quoteID = quoteID; self.lineID = lineID; self._selected = selected
        self.showsSelection = showsSelection; self.edit = edit
    }
    private var line: QuoteLine? { store.quote(quoteID)?.lines.first { $0.id == lineID } }
    private func update(_ change: (inout QuoteLine) -> Void) {
        guard var line else { return }
        let alreadyConfirmed = line.isReviewed
        change(&line); line.isReviewed = alreadyConfirmed && WorkflowRules.canConfirm(line)
        store.saveLine(line, in: quoteID)
    }
    var body: some View {
        if let line {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if showsSelection { Toggle("Select \(line.title)", isOn: $selected).labelsHidden() }
                    Text(line.title).font(.headline)
                    Spacer()
                    Button("Edit", action: edit)
                }
                HStack {
                    SourceLabel(source: line.source)
                    Text("\(line.isApproximate == true ? "≈ " : "")\(line.quantity?.editable ?? "Qty missing") \(line.unit)").font(.headline).foregroundStyle(.orange)
                    Spacer()
                    Button { update { $0.quantity = max(1, ($0.quantity ?? 1) - 1) } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Decrease quantity")
                    Button { update { $0.quantity = min(10000, ($0.quantity ?? 0) + 1) } } label: { Image(systemName: "plus.circle") }.accessibilityLabel("Increase quantity")
                }
                if !line.sourceDetail.isEmpty { Text("Evidence: \(line.sourceDetail)").font(.caption).foregroundStyle(.secondary) }
                if let room = line.room, !room.isEmpty { Text(room).font(.caption) }
                if line.workActionRequired == true {
                    Text("Choose the requested work").font(.subheadline).foregroundStyle(.orange)
                    Menu("Install, replace or other work…") {
                        ForEach(WorkAction.allCases, id: \.self) { action in
                            Button(action.rawValue) { update { $0 = WorkflowRules.choosingAction(action, for: $0) } }
                        }
                    }
                } else if let question = line.confirmationPrompt, !question.isEmpty {
                    Text("Check: \(question)").font(.caption).foregroundStyle(.secondary)
                }
                if line.recipeID != nil || line.category == .materials || line.capturedWorkObject != nil {
                    Picker("Who supplies materials?", selection: Binding(get: { line.supply ?? .unknown }, set: { value in update { $0.supply = value } })) {
                        ForEach(MaterialSupply.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.font(.subheadline)
                }
                if line.disposition == .optional {
                    Toggle("Include optional work in this quote", isOn: Binding(get: { line.optionalSelected ?? false }, set: { value in update { $0.optionalSelected = value } }))
                } else if line.disposition == .excluded { Text("Excluded from total").font(.caption).foregroundStyle(.secondary) }
                if let photos = line.linkedPhotos, !photos.isEmpty {
                    ScrollView(.horizontal) { HStack { ForEach(photos, id: \.self) { PhotoThumb(filename: $0) } } }
                }
                HStack {
                    Label(line.isReviewed ? "Confirmed by you" : "Needs your review", systemImage: line.isReviewed ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(line.isReviewed ? .green : .orange)
                    Spacer()
                    if !line.isReviewed {
                        Button("Confirm item") {
                            store.editQuote(quoteID, scopeChanged: true) { quote in
                                if let i = quote.lines.firstIndex(where: { $0.id == lineID }) { quote.lines[i].isReviewed = true }
                            }
                        }.disabled(!WorkflowRules.canConfirm(line))
                    }
                }
            }.padding(13).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct LineEditor: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var line: QuoteLine
    @State private var quantityText: String
    private let original: QuoteLine
    var quoteID: UUID? = nil
    let canDelete: Bool
    let onSave: (QuoteLine) -> Void
    let onDelete: () -> Void
    init(line: QuoteLine, quoteID: UUID? = nil, canDelete: Bool, onSave: @escaping (QuoteLine) -> Void, onDelete: @escaping () -> Void) {
        _line = State(initialValue: line); original = line; _quantityText = State(initialValue: line.quantity?.editable ?? "")
        self.quoteID = quoteID; self.canDelete = canDelete; self.onSave = onSave; self.onDelete = onDelete
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Work and quantity") {
                    if line.workActionRequired == true {
                        Text("Your note names items but does not say what work to do.").foregroundStyle(.orange)
                        Menu("Choose requested work…") {
                            ForEach(WorkAction.allCases, id: \.self) { action in
                                Button(action.rawValue) { line = WorkflowRules.choosingAction(action, for: line) }
                            }
                        }
                    }
                    TextField("Work requested", text: $line.title)
                    Picker("Category", selection: $line.category) { ForEach(LineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    HStack { TextField("Quantity", text: $quantityText).keyboardType(.decimalPad); TextField("Unit", text: $line.unit) }
                    Toggle("Approximate allowance", isOn: Binding(get: { line.isApproximate ?? false }, set: { line.isApproximate = $0 }))
                    TextField("Room / location", text: Binding(get: { line.room ?? "" }, set: { line.room = $0 }))
                    Picker("Scope", selection: Binding(get: { line.disposition ?? .included }, set: { line.disposition = $0 })) {
                        ForEach(ScopeDisposition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Job recipe and optional details") {
                    Picker("Recipe", selection: $line.recipeID) {
                        Text("Custom work").tag(nil as UUID?)
                        ForEach(store.recipes) { Text($0.name).tag(Optional($0.id)) }
                    }.onChange(of: line.recipeID) { _, id in
                        guard let recipe = store.recipes.first(where: { $0.id == id }) else { return }
                        line.title = recipe.name; line.unit = recipe.unit; line.category = .labour
                        line.workActionRequired = false
                        line.confirmationPrompt = recipe.specificationQuestion.isEmpty ? nil : recipe.specificationQuestion
                        line.confirmationKind = .specification
                        if !recipe.asksSupply { line.supply = MaterialSupply.none }
                        else if line.supply == nil || line.supply == MaterialSupply.none { line.supply = .unknown }
                        line.needsRateMatch = false
                    }
                    if let question = line.confirmationPrompt { Text("Check: \(question)").foregroundStyle(.secondary) }
                    TextField("Extra specifications (optional)", text: $line.specification, axis: .vertical).lineLimit(2...6)
                    Text("Add details you want included in the PDF. You can leave this blank.").font(.caption).foregroundStyle(.secondary)
                    Picker("Material supply", selection: Binding(get: { line.supply ?? .unknown }, set: { line.supply = $0 })) {
                        ForEach(MaterialSupply.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if let recipe = store.recipes.first(where: { $0.id == line.recipeID }) {
                        if !recipe.inclusions.isEmpty { Text("Standard inclusions to check: \(recipe.inclusions)").font(.caption) }
                        if !recipe.exclusions.isEmpty { Text("Standard exclusions to check: \(recipe.exclusions)").font(.caption) }
                        if !recipe.inclusions.isEmpty || !recipe.exclusions.isEmpty {
                            Button("Append checked recipe wording") {
                                line.specification += "\n" + [recipe.inclusions.isEmpty ? "" : "Includes: " + recipe.inclusions, recipe.exclusions.isEmpty ? "" : "Excludes: " + recipe.exclusions].filter { !$0.isEmpty }.joined(separator: "\n")
                            }
                        }
                    }
                }
                Section("Evidence") {
                    SourceLabel(source: line.source)
                    Text(line.sourceDetail).font(.footnote)
                    if let quoteID, let quote = store.quote(quoteID) {
                        ForEach(quote.photoNames, id: \.self) { name in
                            Toggle(isOn: Binding(get: { line.linkedPhotos?.contains(name) ?? false }, set: { flag in
                                var photos = line.linkedPhotos ?? []; photos.removeAll { $0 == name }; if flag { photos.append(name) }; line.linkedPhotos = photos
                            })) { PhotoThumb(filename: name) }
                        }
                    }
                }
                Section {
                    Text("Save & confirm approves this item's work, quantity and material supply. Incomplete items can be saved as drafts.").font(.caption).foregroundStyle(.secondary)
                    if let quoteID, let recipe = store.recipes.first(where: { $0.id == line.recipeID }), !recipe.components.isEmpty, canDelete {
                        Button("Save and expand configured recipe components") {
                            finish(); store.expandRecipe(for: line.id, in: quoteID)
                        }.disabled((quantityText.asDecimal ?? 0) <= 0 || line.supply == .unknown)
                    }
                }
                if canDelete { Button("Delete item", role: .destructive) { onDelete(); dismiss() } }
            }
            .keyboardDoneButton().navigationTitle("Edit item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(canConfirmEdit ? "Save & confirm" : "Save draft", action: finish).disabled(line.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
    private func finish() {
        line.quantity = quantityText.asDecimal
        line.isReviewed = WorkflowRules.canConfirm(line)
        if line.category != original.category || !QuoteRules.unitsMatch(line.unit, original.unit) || line.recipeID != original.recipeID { line.rateID = nil }
        onSave(line); dismiss()
    }
    private var canConfirmEdit: Bool {
        var draft = line; draft.quantity = quantityText.asDecimal
        return WorkflowRules.canConfirm(draft)
    }
}
