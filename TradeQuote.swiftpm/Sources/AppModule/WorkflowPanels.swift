import SwiftUI
import UserNotifications
import QuoteCore

struct LabourBillingPanel: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    var body: some View {
        if let quote = store.quote(quoteID) {
            VStack(alignment: .leading, spacing: 10) {
                Heading(text: "How will you charge labour?")
                Picker("Labour billing", selection: Binding<LabourBilling?>(get: { store.quote(quoteID)?.billingMethod }, set: { method in
                    store.editQuote(quoteID, scopeChanged: true) { $0.billingMethod = method }
                })) {
                    Text("Choose method").tag(nil as LabourBilling?)
                    ForEach(LabourBilling.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                switch quote.billingMethod {
                case .hourly:
                    Text("Only labour-hour lines are charged. Task quantities describe the work covered by those hours.").font(.caption)
                    if !quote.lines.contains(where: { $0.category == .labour && QuoteRules.unitsMatch($0.unit, "h") && WorkflowRules.included($0) }) {
                        Button("Add whole-job labour hours") {
                            store.saveLine(QuoteLine(title: "Whole-job labour allowance", category: .labour, source: .manual, unit: "h"), in: quoteID)
                        }
                    }
                case .perTask:
                    Text("Labour is charged per task. Any hour lines remain internal allowances and are excluded from the total.").font(.caption)
                case .fixed:
                    Text("All included labour tasks are covered by one agreed labour amount. Materials are priced separately.").font(.caption)
                    DecimalEntry(title: "Fixed labour price", value: Binding(get: { store.quote(quoteID)?.fixedLabourPrice }, set: { value in
                        store.editQuote(quoteID, scopeChanged: true) { $0.fixedLabourPrice = value }
                    }))
                case nil:
                    Text("Choose one method before pricing. Existing quotations retain their original amounts.").font(.caption).foregroundStyle(.orange)
                }
            }.padding(13).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
struct DecimalEntry: View {
    let title: String
    @Binding var value: Decimal?
    @State private var text = ""
    var body: some View {
        TextField(title, text: $text).keyboardType(.decimalPad)
            .onAppear { text = value?.editable ?? "" }
            .onChange(of: text) { _, new in
                let parsed = new.isEmpty ? nil : new.asDecimal
                if parsed != value { value = parsed }
            }
    }
}
struct VersionHistoryView: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let quoteID: UUID
    @State private var restore: QuoteVersion?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Restore a scope checkpoint. Restored work requires fresh approval. Up to 25 checkpoints are retained.").font(.subheadline) }
                ForEach((store.quote(quoteID)?.versions ?? []).reversed()) { version in
                    Button { restore = version } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(version.reason).font(.headline)
                            Text("\(version.date.formatted()) · \(version.lines.count) items").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Scope history")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Restore this scope?", isPresented: Binding(get: { restore != nil }, set: { if !$0 { restore = nil } }), titleVisibility: .visible) {
                Button("Restore and review") { if let restore { store.restoreVersion(restore, in: quoteID) }; dismiss() }
            } message: { Text("The current scope will also be saved as a checkpoint. Pricing and scope approvals will be cleared.") }
        }
    }
}
struct CommercialTermsView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    @State private var reminderMessage: String?
    var body: some View {
        if let quote = store.quote(quoteID) {
            VStack(alignment: .leading, spacing: 12) {
                Heading(text: "Validity and payment")
                DatePicker("Quote expires", selection: Binding(get: { store.quote(quoteID)?.expiresAt ?? Date() }, set: { date in store.editQuote(quoteID) { $0.expiresAt = date } }), displayedComponents: .date)
                DecimalEntry(title: "Deposit percentage (optional)", value: Binding(get: { store.quote(quoteID)?.depositPercent }, set: { value in store.editQuote(quoteID) { $0.depositPercent = value } }))
                TextField("Payment schedule (optional)", text: Binding(get: { store.quote(quoteID)?.paymentSchedule ?? "" }, set: { value in store.editQuote(quoteID) { $0.paymentSchedule = value } }), axis: .vertical)
                Toggle("Remind me to follow up", isOn: Binding(get: { store.quote(quoteID)?.followUpAt != nil }, set: { flag in
                    store.editQuote(quoteID) { $0.followUpAt = flag ? Date().addingTimeInterval(3 * 86400) : nil }
                    if !flag { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [quoteID.uuidString]) }
                }))
                if quote.followUpAt != nil {
                    DatePicker("Follow up", selection: Binding(get: { store.quote(quoteID)?.followUpAt ?? Date() }, set: { date in store.editQuote(quoteID) { $0.followUpAt = date } }))
                    Button("Schedule device reminder") {
                        Task {
                            do {
                                guard let date = store.quote(quoteID)?.followUpAt, date > Date() else { reminderMessage = "Choose a future reminder time."; return }
                                let center = UNUserNotificationCenter.current()
                                guard try await center.requestAuthorization(options: [.alert, .sound]) else { reminderMessage = "Enable notifications in Settings to receive reminders."; return }
                                let content = UNMutableNotificationContent()
                                content.title = "Follow up on \(quote.number)"
                                content.body = "Check the customer response to \(quote.title)."
                                content.sound = .default
                                try await center.add(UNNotificationRequest(identifier: quoteID.uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
                                reminderMessage = "Reminder scheduled on this device. No message is sent to the customer."
                            } catch { reminderMessage = error.localizedDescription }
                        }
                    }
                }
                if let reminderMessage { Text(reminderMessage).font(.caption).foregroundStyle(.secondary) }
            }.padding(13).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
