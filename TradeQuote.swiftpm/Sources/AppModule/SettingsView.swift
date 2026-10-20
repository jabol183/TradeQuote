import SwiftUI
import FoundationModels
import QuoteCore

private enum SettingsPanel: String, Identifiable {
    case business = "Business Details"
    case vat = "VAT Settings"
    case terms = "Quote Templates"
    case units = "Units & Defaults"
    case voice = "Siri & Voice"
    case ai = "On-Device AI"
    case privacy = "Data & Privacy"
    var id: String { rawValue }
}

struct SettingsView: View {
    @Environment(TradeQuoteStore.self) private var store
    @State private var selected: SettingsPanel?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(Theme.blue)
                    VStack(alignment: .leading) {
                        Text(store.business.name.isEmpty ? "Set up your business" : store.business.name)
                            .fontWeight(.semibold)
                        Text(store.business.email.isEmpty ? "Local-first TradeQuote AI" : store.business.email)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 7)
            }
            Section {
                row("Business Details", icon: "building.2", panel: .business)
                row("Rate Card", icon: "tag", panel: nil)
                row("Quote Templates", icon: "doc.text", panel: .terms)
                row("VAT Settings", icon: "percent", panel: .vat)
                row("Units & Defaults", icon: "ruler", panel: .units)
            }
            Section {
                row("Siri & Voice", icon: "waveform", panel: .voice)
                row("On-Device AI", icon: "sparkles", panel: .ai)
                row("Data & Privacy", icon: "lock.shield", panel: .privacy)
            }
            Section {
                Text("TradeQuote AI · Version 1.0\nQuotes and job photos are stored locally on this device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(item: $selected) { panel in
            NavigationStack {
                SettingsPanelView(panel: panel)
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, icon: String, panel: SettingsPanel?) -> some View {
        Button {
            if let panel { selected = panel }
            else { selected = .units }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.blue).frame(width: 23)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsPanelView: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let panel: SettingsPanel
    @State private var draft = BusinessProfile()
    @State private var vatString = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            switch panel {
            case .business:
                Section("Contractor identity shown on PDFs") {
                    TextField("Trading / business name", text: $draft.name)
                    TextField("Email", text: $draft.email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Phone", text: $draft.telephone).keyboardType(.phonePad)
                    TextField("Postal business address", text: $draft.address, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("VAT / tax registration no. (optional)", text: $draft.taxIdentifier)
                }
            case .vat:
                Section("Contractor-configured tax") {
                    TextField("VAT percentage (0 if not applicable)", text: $vatString)
                        .keyboardType(.decimalPad)
                    Text("There is no assumed VAT percentage. Enter the rate applicable to your business and this quote.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .terms:
                Section("Default quotation terms") {
                    TextEditor(text: $draft.terms)
                        .frame(minHeight: 150)
                }
            case .units:
                Section("Currency") {
                    Picker("Currency", selection: $draft.currencyCode) {
                        Text("British Pound (GBP)").tag("GBP")
                        Text("Euro (EUR)").tag("EUR")
                        Text("Polish Złoty (PLN)").tag("PLN")
                        Text("US Dollar (USD)").tag("USD")
                    }
                    Text("Changing currency only changes the denomination; there is no FX conversion. Existing approved quotations retain the currency in which their rates were approved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .voice:
                Section {
                    Label("Dictation is transcribed through Apple's on-device Speech Recognition engine.", systemImage: "waveform")
                    Text("An English (UK) on-device speech model must be installed. If it is unavailable, you can type the job description.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Use the Shortcuts app to launch TradeQuote quickly. Automatic Siri quote generation is not enabled.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            case .ai:
                Section {
                    switch SystemLanguageModel.default.availability {
                    case .available:
                        Label("Apple Foundation Models is available on this device.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    default:
                        Label("Apple Foundation Models unavailable", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Check Apple Intelligence compatibility, the model download, settings and supported operating system.")
                    }
                    Text("Model outputs are unapproved suggestions. Every quantity and specification requires contractor review; prices are never generated by AI.")
                        .font(.subheadline)
                }
            case .privacy:
                Section {
                    Label("All quote data is saved in the app's local Documents folder.", systemImage: "internaldrive")
                    Label("Photographs are resized and stored locally.", systemImage: "photo")
                    Label("Quote PDFs are shared only at your direction.", systemImage: "square.and.arrow.up")
                    Label("No analytics, ad SDK, account sync or external LLM API.", systemImage: "lock.shield")
                    Text("Uninstalling the app may delete its data. Back up critical PDFs using the Share button.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(panel.rawValue)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(panel.isEditable ? "Cancel" : "Done") { dismiss() }
            }
            if panel.isEditable {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if panel == .vat { draft.vatPercent = vatString.asDecimal }
                        store.updateBusiness(draft)
                        dismiss()
                    }
                    .disabled(panel == .vat && (vatString.asDecimal == nil ||
                              (vatString.asDecimal ?? -1) < 0 || (vatString.asDecimal ?? 101) > 100))
                }
            }
        }
        .onAppear {
            if !didLoad {
                draft = store.business
                vatString = draft.vatPercent?.editable ?? ""
                didLoad = true
            }
        }
    }
}
private extension SettingsPanel {
    var isEditable: Bool {
        switch self {
        case .business, .vat, .terms, .units: true
        case .voice, .ai, .privacy: false
        }
    }
}
