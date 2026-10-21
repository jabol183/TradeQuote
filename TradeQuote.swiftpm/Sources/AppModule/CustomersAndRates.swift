import SwiftUI
import QuoteCore
import UniformTypeIdentifiers

struct CustomersView: View {
    @Environment(TradeQuoteStore.self) private var store
    let open: (Quote) -> Void
    @State private var editing: Customer?
    @State private var search = ""

    private var filtered: [Customer] {
        store.customers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) ||
            $0.email.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            ForEach(filtered) { customer in
                NavigationLink {
                    CustomerDetailsView(customerID: customer.id, open: open)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 35))
                            .foregroundStyle(.gray.opacity(0.6))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(customer.name).font(.subheadline.weight(.semibold))
                            Text(customer.email.isEmpty ? customer.address : customer.email)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(store.quotes.filter { $0.customerID == customer.id }.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    // Customers on a quote stay, so quote history and PDFs keep their recipient.
                    if store.canDeleteCustomer(customer.id) {
                        Button("Delete", role: .destructive) { store.deleteCustomer(customer.id) }
                    }
                }
            }
        }
        .searchable(text: $search)
        .overlay {
            if filtered.isEmpty { BlankState(icon: "person.2", title: "No customers yet", detail: "Add a customer to associate them with quotations.") }
        }
        .navigationTitle("Customers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = Customer() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { customer in
            CustomerEditor(customer: customer) { store.updateCustomer($0) }
        }
    }
}

struct CustomerDetailsView: View {
    @Environment(TradeQuoteStore.self) private var store
    let customerID: UUID
    let open: (Quote) -> Void
    @State private var editing: Customer?

    var body: some View {
        List {
            if let customer = store.customer(customerID) {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(customer.name).font(.title2.bold())
                        Label(customer.phone.isEmpty ? "No phone set" : customer.phone, systemImage: "phone")
                        Label(customer.email.isEmpty ? "No email set" : customer.email, systemImage: "envelope")
                        Label(customer.address.isEmpty ? "No address set" : customer.address, systemImage: "mappin")
                    }
                    Button("Edit customer") { editing = customer }
                }
                Section("Quotes") {
                    let quotes = store.quotes.filter { $0.customerID == customerID }
                    ForEach(quotes) { quote in
                        Button { open(quote) } label: { QuoteRow(quote: quote) }
                            .buttonStyle(.plain)
                    }
                    if quotes.isEmpty { Text("No quotes yet.").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Customer History")
        .sheet(item: $editing) { customer in
            CustomerEditor(customer: customer) { store.updateCustomer($0) }
        }
    }
}

struct CustomerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customer: Customer
    let onSave: (Customer) -> Void

    init(customer: Customer, onSave: @escaping (Customer) -> Void) {
        _customer = State(initialValue: customer)
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $customer.name)
                        .textContentType(.name)
                    TextField("Email", text: $customer.email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().textContentType(.emailAddress)
                    TextField("Phone", text: $customer.phone).keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Postal address", text: $customer.address, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(customer); dismiss() }
                        .disabled(customer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct RateCardView: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// True when shown as a pop-up sheet (from Pricing or Settings) rather than as a tab.
    var showsDone = false
    @State private var category: LineCategory = .labour
    @State private var editing: Rate?
    @State private var search = ""
    @State private var importCSV = false
    @State private var imported: [Rate] = []
    @State private var showImportPreview = false
    @State private var importError: String?
    private var filteredRates: [Rate] {
        store.rates.filter { rate in
            rate.category == category && (search.isEmpty || ([rate.name, rate.productCode ?? ""] + (rate.aliases ?? [])).contains(where: { $0.localizedCaseInsensitiveContains(search) }))
        }.sorted { $0.isFavourite == true && $1.isFavourite != true ? true : ($0.isFavourite != true && $1.isFavourite == true ? false : $0.name < $1.name) }
    }

    var body: some View {
        List {
            Section {
                Picker("Rate type", selection: $category) {
                    ForEach(LineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("\(category.rawValue) rates") {
                ForEach(filteredRates) { rate in
                    Button { editing = rate } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text((rate.isFavourite == true ? "★ " : "") + rate.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                if let date = rate.updatedAt { Text("Checked \(date.quoteDate)").font(.caption2).foregroundStyle(.secondary) }
                                Text("Per \(rate.unit)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(rate.amount.map { QuotePDF.money($0, store.business.currencyCode) } ?? "Rate not set")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(rate.amount == nil ? Color.orange : Color.primary)
                            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.deleteRate(rate.id) }
                    }
                }
            }
            Section {
                Button("Import price list (CSV)") { importCSV = true }
                Text("Columns: name,category,unit,amount. Optional: aliases (separated by |), productcode,purchasecost. Preview before importing; matching names, categories and units update existing rates.").font(.caption)
                if let importError { Text(importError).foregroundStyle(.red) }
                Label("Only rates you enter here can be used to approve a quote. No sample amounts are preloaded.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search)
        .fileImporter(isPresented: $importCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 5_000_000 else { throw RateCSV.Failure.invalid("Import a CSV smaller than 5 MB.") }
                imported = try RateCSV.parse(String(contentsOf: url, encoding: .utf8)); showImportPreview = true; importError = nil
            } catch { importError = error.localizedDescription }
        }
        .sheet(isPresented: $showImportPreview) {
            NavigationStack {
                List(imported) { rate in
                    VStack(alignment: .leading) { Text(rate.name); Text("\(rate.category.rawValue) / \(rate.unit) · \(rate.amount?.editable ?? "Rate not set")").font(.caption) }
                }
                .navigationTitle("Import \(imported.count) rates")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showImportPreview = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Import") { store.importRates(imported); showImportPreview = false }.disabled(imported.isEmpty) }
                }
            }
        }
        .navigationTitle("Rate Card")
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { editing = Rate(name: "", category: category, unit: category == .labour ? "h" : "each") } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { item in
            RateEditor(rate: item, currency: store.business.currencyCode) {
                store.updateRate($0)
            }
        }
    }
}

struct RateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rate: Rate
    @State private var priceString: String
    @State private var aliases = ""
    @State private var cost = ""
    @State private var markup = ""
    let currency: String
    let onSave: (Rate) -> Void

    init(rate: Rate, currency: String, onSave: @escaping (Rate) -> Void) {
        _rate = State(initialValue: rate)
        _priceString = State(initialValue: rate.amount?.editable ?? "")
        self.currency = currency
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your rate") {
                    TextField("Name", text: $rate.name)
                    Picker("Category", selection: $rate.category) {
                        ForEach(LineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Unit (each, h, m…)", text: $rate.unit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text("Price (\(currency))")
                        Spacer()
                        TextField("Not set", text: $priceString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Catalogue details") {
                    TextField("Product / service code", text: Binding(get: { rate.productCode ?? "" }, set: { rate.productCode = $0 }))
                    TextField("Alternative names, separated by commas", text: $aliases, axis: .vertical)
                    Toggle("Favourite", isOn: Binding(get: { rate.isFavourite ?? false }, set: { rate.isFavourite = $0 }))
                    TextField("Purchase cost", text: $cost).keyboardType(.decimalPad)
                    TextField("Markup percentage", text: $markup).keyboardType(.decimalPad)
                    Button("Calculate selling price from cost + markup") {
                        if let base = cost.asDecimal, let percent = markup.asDecimal { priceString = QuoteRules.roundMoney(base * (1 + percent / 100)).editable }
                    }.disabled(cost.asDecimal == nil || markup.asDecimal == nil || (markup.asDecimal ?? -1) < 0)
                    if let price = priceString.asDecimal, let base = cost.asDecimal, price > 0 {
                        Text("Gross margin: \(QuoteRules.roundMoney((price - base) / price * 100).editable)%").font(.caption)
                    }
                    Text("Markup is a percentage added to cost. Gross margin is profit divided by selling price.").font(.caption)
                }
                Section {
                    Text("Leave the price blank to keep Rate not set. All costs are entered by the contractor.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .keyboardDoneButton()
            .onAppear { aliases = (rate.aliases ?? []).joined(separator: ", "); cost = rate.purchaseCost?.editable ?? "" }
            .navigationTitle("Edit Rate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        rate.amount = priceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : priceString.asDecimal
                        rate.aliases = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        rate.purchaseCost = cost.asDecimal
                        rate.updatedAt = Date()
                        onSave(rate)
                        dismiss()
                    }
                    .disabled(rate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              rate.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!priceString.isEmpty && (priceString.asDecimal == nil || (priceString.asDecimal ?? -1) < 0)) ||
                              (!cost.isEmpty && (cost.asDecimal == nil || (cost.asDecimal ?? -1) < 0)))
                }
            }
        }
    }
}

