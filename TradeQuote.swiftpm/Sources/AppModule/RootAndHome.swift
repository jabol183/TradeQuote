import SwiftUI
import QuoteCore

enum FlowStep: Hashable {
    case capture, review, pricing, preview, details, send
}

struct QuoteRoute: Identifiable {
    let id = UUID()
    let quoteID: UUID
    let start: FlowStep
}

struct RootView: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var route: QuoteRoute?
    @State private var showStoreFailure = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView(open: open, newQuote: newQuote, selectTab: { selectedTab = $0 }) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { QuotesListView(open: open, newQuote: newQuote) }
                .tabItem { Label("Quotes", systemImage: "doc.text") }.tag(1)
            NavigationStack { CustomersView(open: open) }
                .tabItem { Label("Customers", systemImage: "person.2") }.tag(2)
            NavigationStack { RateCardView() }
                .tabItem { Label("Rate Card", systemImage: "sterlingsign.circle") }.tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .sheet(item: $route) { item in
            QuoteFlowView(quoteID: item.quoteID, start: item.start)
        }
        .alert("Storage issue", isPresented: $showStoreFailure) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.failureMessage ?? "An unknown save error occurred.")
        }
        .onChange(of: store.failureMessage) { _, value in
            showStoreFailure = value != nil
        }
        .onAppear {
            showStoreFailure = store.failureMessage != nil
            handlePendingShortcut()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handlePendingShortcut() }
            else { store.saveNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startNewTradeQuote)) { _ in
            handlePendingShortcut()
        }
    }

    private func handlePendingShortcut() {
        guard UserDefaults.standard.bool(forKey: "TradeQuote.PendingNewQuote") else { return }
        UserDefaults.standard.set(false, forKey: "TradeQuote.PendingNewQuote")
        selectedTab = 0
        newQuote()
    }

    private func open(_ quote: Quote) { route = QuoteRoute(quoteID: quote.id, start: quote.status == .draft ? .review : .details) }
    private func newQuote() { route = QuoteRoute(quoteID: store.newQuote(), start: .capture) }
}

struct HomeView: View {
    @Environment(TradeQuoteStore.self) private var store
    let open: (Quote) -> Void
    let newQuote: () -> Void
    let selectTab: (Int) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TradeQuote AI").font(.largeTitle.bold())
                        Text("Your quotes. Your rates. Your control.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .font(.title2).foregroundStyle(Theme.blue)
                }
                .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 12) {
                    homeTile("Take Photos", "Capture the job", "camera.fill", primary: true, action: newQuote)
                    homeTile("Dictate Job", "Speak naturally", "mic.fill", primary: true, action: newQuote)
                    homeTile("New Quote", "From voice or photos", "doc.badge.plus", action: newQuote)
                    homeTile("Quotes", "View and manage", "doc.text") { selectTab(1) }
                    homeTile("Rate Card", "Your prices and items", "tag") { selectTab(3) }
                    homeTile("Customers", "Contacts and history", "person.2.fill") { selectTab(2) }
                }

                if !store.quotes.filter({ $0.status == .sent && ($0.followUpAt ?? .distantFuture) <= Date() }).isEmpty {
                    Heading(text: "Follow up")
                    ForEach(store.quotes.filter { $0.status == .sent && ($0.followUpAt ?? .distantFuture) <= Date() }) { quote in
                        Button { open(quote) } label: { QuoteRow(quote: quote) }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Heading(text: "Recent Quotes")
                    Spacer()
                    Text("\(store.quotes.count) total").font(.caption).foregroundStyle(.secondary)
                }
                if store.quotes.isEmpty {
                    BlankState(icon: "doc.text", title: "No quotations yet", detail: "Capture photographs or dictate a new job.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.quotes.prefix(5)) { quote in
                            Button { open(quote) } label: { QuoteRow(quote: quote) }
                                .buttonStyle(.plain)
                            if quote.id != store.quotes.prefix(5).last?.id { Divider() }
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(18)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func homeTile(_ title: String, _ subtitle: String, _ icon: String, primary: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: primary ? 31 : 23, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(height: 36)
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 115, alignment: .leading)
            .padding(15)
            .background(primary ? Theme.blue.opacity(0.08) : Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct QuotesListView: View {
    @Environment(TradeQuoteStore.self) private var store
    let open: (Quote) -> Void
    let newQuote: () -> Void
    @State private var filter = "All"
    @State private var search = ""
    @State private var pendingDelete: Quote?
    private let filters = ["All", "Draft", "Ready", "Sent", "Accepted", "Declined"]

    private var filtered: [Quote] {
        store.quotes.filter { quote in
            (filter == "All" || quote.status.rawValue == filter) &&
            (search.isEmpty || quote.title.localizedCaseInsensitiveContains(search) ||
             quote.number.localizedCaseInsensitiveContains(search) ||
             (store.customer(quote.customerID)?.name.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    var body: some View {
        List {
            Picker("Status", selection: $filter) {
                ForEach(filters, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            ForEach(filtered) { quote in
                Button { open(quote) } label: { QuoteRow(quote: quote) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = quote }
                    }
            }
        }
        .searchable(text: $search)
        .confirmationDialog("Delete this quote?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { quote in
            Button("Delete \(quote.number)", role: .destructive) { store.deleteQuote(quote.id) }
        } message: { _ in
            Text("Its photos and PDF are removed from this device. This cannot be undone.")
        }
        .overlay {
            if filtered.isEmpty { BlankState(icon: "doc.text", title: "No matching quotes", detail: "Create a quote or change your filters.") }
        }
        .navigationTitle("Quotations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newQuote) { Image(systemName: "plus") }
            }
        }
    }
}

struct QuoteFlowView: View {
    @Environment(\.dismiss) private var dismiss
    let quoteID: UUID
    let start: FlowStep
    @State private var steps: [FlowStep] = []

    var body: some View {
        NavigationStack(path: $steps) {
            page(for: start)
                .navigationDestination(for: FlowStep.self) { page(for: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                }
        }
    }

    @ViewBuilder
    private func page(for step: FlowStep) -> some View {
        switch step {
        case .capture:
            CaptureView(quoteID: quoteID) {
                // Reached from Review: go back to it instead of stacking a second Review screen.
                if start == .capture { steps.append(.review) } else { steps.removeLast() }
            }
        case .review:
            ReviewView(quoteID: quoteID,
                       addEvidence: start == .review ? { steps.append(.capture) } : nil) { steps.append(.pricing) }
        case .pricing:
            PricingView(quoteID: quoteID) { steps.append(.preview) }
        case .preview:
            QuotePreviewView(quoteID: quoteID) { steps.append(.send) }
        case .send:
            SendQuoteView(quoteID: quoteID)
        case .details:
            QuoteDetailsView(quoteID: quoteID, preview: { steps.append(.preview) })
        }
    }
}

