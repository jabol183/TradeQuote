import SwiftUI
import QuoteCore

struct ReviewView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    let next: () -> Void
    @State private var editing: QuoteLine?
    @State private var addingCustomer = false

    private var quote: Quote? { store.quote(quoteID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Heading(text: "Review items")
                Text("AI-organised scope is a draft. Confirm every item, quantity and material specification before pricing.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let quote {
                    TextField("Job title", text: Binding(
                        get: { store.quote(quoteID)?.title ?? "" },
                        set: { value in store.editQuote(quoteID, scopeChanged: true) { $0.title = value } }
                    ))
                    .font(.title3.bold())
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 8) {
                        Heading(text: "Customer")
                        Picker("Assign customer", selection: Binding(
                            get: { store.quote(quoteID)?.customerID },
                            set: { id in store.editQuote(quoteID) { $0.customerID = id } }
                        )) {
                            Text("Select customer").tag(nil as UUID?)
                            ForEach(store.customers) { customer in
                                Text(customer.name).tag(Optional(customer.id))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            addingCustomer = true
                        } label: { Label("Add customer", systemImage: "plus.circle") }
                            .font(.subheadline)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))

                    ForEach(LineCategory.allCases, id: \.self) { category in
                        let lines = quote.lines.filter { $0.category == category }
                        if !lines.isEmpty {
                            Heading(text: category.rawValue)
                            ForEach(lines) { item in
                                Button { editing = item } label: { itemRow(item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        editing = QuoteLine(title: "", category: .labour, source: .manual, quantity: 1)
                    } label: {
                        Label("Add item manually", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 9)

                    if !quote.photoNames.isEmpty {
                        Heading(text: "Source photos")
                        ScrollView(.horizontal) {
                            HStack { ForEach(quote.photoNames, id: \.self) { PhotoThumb(filename: $0) } }
                        }
                    }

                    ValidationMessages(messages: QuoteRules.reviewProblems(quote).map(\.rawValue))
                    ActionButton(title: quote.reviewApprovedAt == nil ? "Approve scope & continue" : "Continue to pricing",
                                 icon: "checkmark.shield",
                                 disabled: !QuoteRules.reviewProblems(quote).isEmpty) {
                        store.review(quoteID)
                        next()
                    }
                    Text("Your approval confirms the actual work and quantities; the AI does not supply approval.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(17)
        }
        .background(Theme.bg)
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            LineEditor(line: item,
                       canDelete: store.quote(quoteID)?.lines.contains(where: { $0.id == item.id }) == true,
                       onSave: { revised in
                store.editQuote(quoteID, scopeChanged: true) { quote in
                    if let index = quote.lines.firstIndex(where: { $0.id == revised.id }) { quote.lines[index] = revised }
                    else { quote.lines.append(revised) }
                }
                editing = nil
            }, onDelete: {
                store.editQuote(quoteID, scopeChanged: true) { $0.lines.removeAll { $0.id == item.id } }
                editing = nil
            })
        }
        .sheet(isPresented: $addingCustomer) {
            CustomerEditor(customer: Customer()) { store.updateCustomer($0) }
        }
    }

    private func itemRow(_ line: QuoteLine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: line.isReviewed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(line.isReviewed ? .green : .orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(line.title.isEmpty ? "Unnamed item" : line.title)
                    .font(.subheadline.bold()).foregroundStyle(.primary)
                HStack {
                    SourceLabel(source: line.source)
                    Text("· \(line.quantity?.editable ?? "Qty not set") \(line.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if line.confirmationPrompt != nil && (line.specification.isEmpty || !line.isReviewed) {
                    Text("Needs confirmation").font(.caption.weight(.medium)).foregroundStyle(.orange)
                } else if !line.isReviewed {
                    Text("Not yet reviewed").font(.caption).foregroundStyle(.orange)
                }
                if !line.specification.isEmpty { Text(line.specification).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct LineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var line: QuoteLine
    @State private var quantityText: String
    let canDelete: Bool
    let onSave: (QuoteLine) -> Void
    let onDelete: () -> Void

    init(line: QuoteLine, canDelete: Bool, onSave: @escaping (QuoteLine) -> Void, onDelete: @escaping () -> Void) {
        _line = State(initialValue: line)
        _quantityText = State(initialValue: line.quantity?.editable ?? "")
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private let units = ["each", "h", "day", "m", "m²", "set"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Scope") {
                    TextField("Work item", text: $line.title)
                    Picker("Type", selection: $line.category) {
                        ForEach(LineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    HStack {
                        TextField("Quantity", text: $quantityText)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $line.unit) {
                            ForEach(units, id: \.self) { Text($0) }
                        }
                    }
                    TextField("Specification / material / model", text: $line.specification, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Evidence") {
                    SourceLabel(source: line.source)
                    if !line.sourceDetail.isEmpty {
                        Text(line.sourceDetail).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let question = line.confirmationPrompt {
                        Label(question, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section {
                    Toggle("I verified this scope, quantity and specification", isOn: $line.isReviewed)
                        .tint(.green)
                    Text("Confirmation is your decision, never AI-generated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if canDelete {
                    Button("Delete item", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        line.quantity = quantityText.asDecimal
                        if line.quantity == nil || line.quantity! <= 0 || line.title.trimmingCharacters(in: .whitespaces).isEmpty ||
                           (line.confirmationPrompt != nil && line.specification.trimmingCharacters(in: .whitespaces).isEmpty) {
                            line.isReviewed = false
                        }
                        // Changing category may invalidate rate selection; review assigns no rates.
                        line.rateID = nil
                        line.approvedUnitPrice = nil
                        onSave(line)
                        dismiss()
                    }
                    .disabled(line.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
