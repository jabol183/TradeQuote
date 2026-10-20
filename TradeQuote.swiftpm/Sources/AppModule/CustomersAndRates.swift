import SwiftUI
import QuoteCore

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
                    TextField("Email", text: $customer.email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Phone", text: $customer.phone).keyboardType(.phonePad)
                    TextField("Postal address", text: $customer.address, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
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
    @State private var category: LineCategory = .labour
    @State private var editing: Rate?

    var body: some View {
        List {
            Section {
                Picker("Rate type", selection: $category) {
                    ForEach(LineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("\(category.rawValue) rates") {
                ForEach(store.rates.filter { $0.category == category }) { rate in
                    Button { editing = rate } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(rate.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text("Per \(rate.unit)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(rate.amount.map { QuotePDF.money($0, store.business.currencyCode) } ?? "Rate not set")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(rate.amount == nil ? Color.orange : Color.primary)
                            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Label("Only rates you enter here can be used to approve a quote. No sample amounts are preloaded.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Rate Card")
        .toolbar {
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
                    HStack {
                        Text("Price (\(currency))")
                        Spacer()
                        TextField("Not set", text: $priceString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Text("Leave the price blank to keep Rate not set. All costs are entered by the contractor.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Rate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        rate.amount = priceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : priceString.asDecimal
                        onSave(rate)
                        dismiss()
                    }
                    .disabled(rate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              rate.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!priceString.isEmpty && (priceString.asDecimal == nil || (priceString.asDecimal ?? -1) < 0)))
                }
            }
        }
    }
}
