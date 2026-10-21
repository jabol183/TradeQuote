import SwiftUI
import PDFKit
import QuoteCore

struct PricingView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    let next: () -> Void
    @State private var showingRates = false
    @State private var showingSettings = false
    @State private var error: String?
    @State private var editing: QuoteLine?

    private var quote: Quote? { store.quote(quoteID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Heading(text: "Apply pricing")
                Text("Choose labour and material rates from your own rate card. The AI never sets prices.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let quote {
                    LabourBillingPanel(quoteID: quoteID)
                    CommercialTermsView(quoteID: quoteID)
                    if quote.lines.contains(where: { !$0.isReviewed || !WorkflowRules.canConfirm($0) }) {
                        Heading(text: "Confirm changed items here")
                        ForEach(quote.lines.filter { !$0.isReviewed || !WorkflowRules.canConfirm($0) }) { line in
                            ReviewItemCard(quoteID: quoteID, lineID: line.id, selected: .constant(false), showsSelection: false, edit: { editing = line })
                        }
                    }
                    if !quote.materialsConfirmed {
                        Toggle("I checked the materials for the changed work", isOn: Binding(
                            get: { store.quote(quoteID)?.materialsConfirmed ?? false },
                            set: { flag in store.editQuote(quoteID, scopeChanged: true) { $0.materialsConfirmed = flag } }))
                    }
                    ForEach(LineCategory.allCases, id: \.self) { category in
                        let items = quote.lines.filter { $0.category == category }
                        if !items.isEmpty {
                            Heading(text: category.rawValue)
                            ForEach(items) { line in
                                priceRow(line)
                            }
                        }
                    }

                    Button { showingRates = true } label: {
                        Label("Edit rate card / add rates", systemImage: "plus.circle")
                    }
                    .font(.subheadline)
                    Button { showingSettings = true } label: {
                        Label("VAT and business settings", systemImage: "gearshape")
                    }
                    .font(.subheadline)

                    if let vat = quote.approvedVATPercent ?? store.business.vatPercent,
                       let total = QuoteRules.totals(quote, rates: store.rates, vatPercent: vat) {
                        let currency = quote.approvedCurrencyCode ?? store.business.currencyCode
                        VStack(spacing: 10) {
                            sumRow("Subtotal", QuotePDF.money(total.subtotal, currency))
                            sumRow("VAT (\(vat.editable)%)", QuotePDF.money(total.vat, currency))
                            Divider()
                            sumRow("Total", QuotePDF.money(total.total, currency), strong: true)
                        }
                        .padding(17)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 15))
                    }

                    ValidationMessages(messages: QuoteRules.pricingProblems(quote, rates: store.rates, business: store.business, requiresScopeApproval: false).map(\.rawValue))
                    ActionButton(title: quote.reviewApprovedAt == nil ? "Approve changes & pricing" : quote.pricingApprovedAt == nil ? "Approve pricing" : "Continue to quote preview",
                                 icon: "checkmark.shield",
                                 disabled: !QuoteRules.pricingProblems(quote, rates: store.rates, business: store.business, requiresScopeApproval: false).isEmpty) {
                        if quote.pricingApprovedAt != nil && quote.reviewApprovedAt != nil {
                            next()
                        } else if store.approvePricing(quoteID) {
                            next()
                        } else {
                            error = "Please confirm every line, rate and VAT setting."
                        }
                    }
                    Text("Pricing approval freezes the unit prices for this quote. Price changes keep your scope confirmations; changed work can be confirmed here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(17)
        }
        .background(Theme.bg)
        .navigationTitle("Pricing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRates) { NavigationStack { RateCardView(showsDone: true) } }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView(showsDone: true) } }
        .sheet(item: $editing) { line in
            LineEditor(line: line, quoteID: quoteID, canDelete: false,
                onSave: { store.saveLine($0, in: quoteID); editing = nil }, onDelete: {})
        }
        .alert("Check pricing", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func priceRow(_ line: QuoteLine) -> some View {
        let options = WorkflowRules.suggestedRates(for: line, rates: store.rates)
        let rate = store.rates.first { $0.id == line.rateID }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(line.title).font(.subheadline.bold())
                Spacer()
                Button("Edit") { editing = line }.font(.caption)
                Text("\(line.quantity?.editable ?? "?") \(line.unit)").font(.caption).foregroundStyle(.secondary)
            }
            if let quote, !WorkflowRules.isChargeable(line, in: quote) {
                Label(chargeExplanation(line, quote: quote), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            } else {
            Picker("Your rate", selection: Binding(
                get: { store.quote(quoteID)?.lines.first(where: { $0.id == line.id })?.rateID },
                set: { value in
                    store.editQuote(quoteID, pricingChanged: true) { q in
                        guard let index = q.lines.firstIndex(where: { $0.id == line.id }) else { return }
                        q.lines[index].rateID = value
                        if let value, options.contains(where: { $0.id == value }) { q.lines[index].needsRateMatch = false }
                    }
                }
            )) {
                Text("Rate not set").tag(nil as UUID?)
                ForEach(options) { rate in
                    Text("\(rate.name) (\(rate.amount.map { QuotePDF.money($0, store.business.currencyCode) } ?? "Rate not set"))")
                        .tag(Optional(rate.id))
                }
            }
            .pickerStyle(.menu)
            if options.isEmpty {
                Text("No saved \(line.category.rawValue.lowercased()) rate is priced per \(line.unit). Add one in the rate card.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let amount = quote?.pricingApprovedAt != nil ? line.approvedUnitPrice : rate?.amount,
               let quantity = line.quantity {
                HStack {
                    Text(QuotePDF.money(amount, store.business.currencyCode) + " / " + line.unit)
                    Spacer()
                    Text(QuotePDF.money(QuoteRules.roundMoney(quantity * amount), store.business.currencyCode))
                        .fontWeight(.semibold)
                }
                .font(.footnote)
            } else {
                Label("Rate not set", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            }
        }
        .padding(13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func chargeExplanation(_ line: QuoteLine, quote: Quote) -> String {
        if !WorkflowRules.included(line) { return "Not included in the total" }
        if line.isRecipeContainer == true { return "Scope heading; configured components are priced separately" }
        if line.category == .materials { return "Materials supplied by customer / no purchase charge" }
        if quote.billingMethod == .perTask { return "Internal time allowance; task rates cover labour" }
        return quote.billingMethod == .fixed ? "Included in fixed labour total" : "Covered by whole-job labour hours"
    }

    private func sumRow(_ title: String, _ value: String, strong: Bool = false) -> some View {
        HStack {
            Text(title).font(strong ? .headline : .subheadline)
            Spacer()
            Text(value).font(strong ? .headline : .subheadline).fontWeight(strong ? .bold : .regular)
        }
    }
}

struct PDFSheetView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = UIColor.secondarySystemGroupedBackground
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

struct QuotePreviewView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    let next: () -> Void
    @State private var previewData: Data?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 13) {
            if let quote = store.quote(quoteID) {
                if quote.finalizedAt == nil {
                    Picker("Customer", selection: Binding(
                        get: { store.quote(quoteID)?.customerID },
                        set: { value in store.editQuote(quoteID) { $0.customerID = value }; refresh() }
                    )) {
                        Text("Select customer").tag(nil as UUID?)
                        ForEach(store.customers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .padding(.horizontal, 15)
                }
                if let previewData {
                    PDFSheetView(data: previewData)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    BlankState(icon: "doc.richtext", title: "Preview unavailable", detail: error ?? "Approve the reviewed pricing to see a preview.")
                }

                let problems = QuoteRules.finalizationProblems(quote, rates: store.rates, business: store.business, customers: store.customers)
                if quote.finalizedAt == nil {
                    ValidationMessages(messages: problems.map(\.rawValue))
                    ActionButton(title: "Generate final PDF", icon: "doc.badge.arrow.up",
                                 disabled: !problems.isEmpty) {
                        do {
                            _ = try store.saveFinalPDF(quoteID)
                            next()
                        } catch { self.error = error.localizedDescription }
                    }
                } else {
                    ActionButton(title: "Send / share quotation", icon: "square.and.arrow.up", action: next)
                }
            }
        }
        .padding(14)
        .background(Theme.bg)
        .navigationTitle("Quote Preview")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: store.business) { _, _ in refresh() }
        .alert("PDF generation", isPresented: Binding(
            get: { error != nil && previewData != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func refresh() {
        guard let quote = store.quote(quoteID), quote.pricingApprovedAt != nil else { previewData = nil; return }
        if let url = store.pdfURL(quoteID), let persisted = try? Data(contentsOf: url) {
            previewData = persisted
            return
        }
        let customer = store.customer(quote.customerID) ?? Customer(name: "Customer not selected")
        do {
            previewData = try QuotePDF.generate(quote: quote, business: store.business, customer: customer, rates: store.rates)
        } catch {
            previewData = nil
            self.error = error.localizedDescription
        }
    }
}

struct SendQuoteView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Heading(text: "Send quote")
                Text("Your contractor-approved PDF is ready. Share it with your customer using an app of your choice.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let q = store.quote(quoteID), let url = store.shareablePDF(quoteID) {
                    HStack {
                        Image(systemName: "doc.richtext.fill").font(.title).foregroundStyle(Theme.blue)
                        VStack(alignment: .leading) {
                            Text(q.number + ".pdf").fontWeight(.semibold)
                            Text(store.customer(q.customerID)?.email ?? "Choose recipient in your mail app")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 15))
                    ShareLink(item: url, preview: SharePreview(q.number)) {
                        Label("Share PDF quotation", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)

                    if q.status == .final {
                        Button("Mark as sent (after actually sending)") {
                            store.setStatus(.sent, for: quoteID)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    Label("Sharing doesn't confirm delivery. You control when to mark a quote as sent or accepted.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    BlankState(icon: "exclamationmark.circle", title: "No final PDF", detail: "Generate the PDF from Quote Preview first.")
                }
            }
            .padding(17)
        }
        .background(Theme.bg)
        .navigationTitle("Share")
    }
}

struct QuoteDetailsView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    let preview: () -> Void
    @State private var duplicateMessage = false
    @State private var materialsURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let quote = store.quote(quoteID) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(quote.number).font(.title2.bold())
                            Text(quote.title).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusLabel(status: quote.status)
                    }
                    .padding(.top, 10)

                    if let customer = store.customer(quote.customerID) {
                        Heading(text: "Customer")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(customer.name).fontWeight(.semibold)
                            Text(customer.address)
                            Text(customer.email)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 15))
                    }
                    Heading(text: "Quote items")
                    ForEach(quote.lines) { line in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(line.title).fontWeight(.semibold)
                                SourceLabel(source: line.source)
                            }
                            Spacer()
                            Text("\(line.quantity?.editable ?? "?") \(line.unit)")
                            if let price = line.approvedUnitPrice, let qty = line.quantity {
                                Text(QuotePDF.money(QuoteRules.roundMoney(price * qty), quote.approvedCurrencyCode ?? store.business.currencyCode))
                            }
                        }
                        .font(.subheadline).padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let original = quote.revisionOf { Text("Revision of \(original)").font(.subheadline) }
                    if let expiry = quote.expiresAt { Text("Valid until \(expiry.quoteDate)").font(.subheadline) }
                    Button("Prepare materials list") {
                        do { materialsURL = try store.materialsList(quoteID) }
                        catch { exportError = error.localizedDescription }
                    }
                    if let materialsURL { ShareLink("Share materials list", item: materialsURL) }
                    if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
                    Heading(text: "Timeline")
                    VStack(alignment: .leading, spacing: 12) {
                        timeline("Created", quote.createdAt)
                        if let date = quote.reviewApprovedAt { timeline("Scope approved", date) }
                        if let date = quote.pricingApprovedAt { timeline("Pricing approved", date) }
                        if let date = quote.finalizedAt { timeline("PDF generated", date) }
                        if let date = quote.sentAt { timeline("Marked as sent", date) }
                        if let date = quote.responseRecordedAt {
                            timeline("Customer response: \(quote.status.rawValue)", date)
                        }
                    }.font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

                    if quote.finalizedAt != nil {
                        Menu {
                            Button("Mark sent") { store.setStatus(.sent, for: quoteID) }
                            Button("Mark accepted") { store.setStatus(.accepted, for: quoteID) }
                            Button("Mark declined") { store.setStatus(.declined, for: quoteID) }
                        } label: {
                            Label("Update customer response", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity).padding(12)
                        }
                        .buttonStyle(.bordered)
                        ActionButton(title: "View final PDF", icon: "doc.text", action: preview)
                    }
                    Button {
                        duplicateMessage = store.duplicate(quoteID) != nil
                    } label: { Label("Create revised quotation", systemImage: "doc.on.doc") }
                    .padding(.vertical, 12)
                }
            }
            .padding(17)
        }
        .background(Theme.bg)
        .navigationTitle("Quote Status")
        .alert("Draft created", isPresented: $duplicateMessage) {
            Button("OK") {}
        } message: { Text("Your copy appears in Quotations, ready for editing and fresh approval.") }
    }

    private func timeline(_ text: String, _ date: Date) -> some View {
        HStack {
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
            Text(text)
            Spacer()
            Text(date.quoteDate).foregroundStyle(.secondary)
        }
    }
}

