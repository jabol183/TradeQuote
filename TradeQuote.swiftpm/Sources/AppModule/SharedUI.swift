import SwiftUI
import UIKit
import QuoteCore

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }
}

struct Heading: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusLabel: View {
    let status: QuoteStatus
    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
    private var tint: Color {
        switch status {
        case .draft: .gray
        case .final: .purple
        case .sent: .blue
        case .accepted: .green
        case .declined: .red
        }
    }
}

struct QuoteRow: View {
    @Environment(TradeQuoteStore.self) private var store
    let quote: Quote

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(Theme.blue)
                .frame(width: 38, height: 38)
                .background(Theme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(store.customer(quote.customerID)?.name ?? quote.number)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                if let vat = quote.approvedVATPercent,
                   let amounts = QuoteRules.totals(quote, rates: store.rates, vatPercent: vat) {
                    Text(QuotePDF.money(amounts.total, quote.approvedCurrencyCode ?? store.business.currencyCode)).font(.subheadline.weight(.semibold))
                }
                StatusLabel(status: quote.status)
            }
        }
        .padding(.vertical, 5)
    }
}

struct SourceLabel: View {
    let source: EvidenceSource
    var body: some View {
        Label(source.rawValue, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
    private var icon: String {
        switch source {
        case .voice: "waveform"
        case .photo: "camera"
        case .manual: "hand.draw"
        case .note: "text.alignleft"
        }
    }
}

struct PhotoThumb: View {
    @Environment(TradeQuoteStore.self) private var store
    let filename: String
    var body: some View {
        Group {
            if let image = store.photo(named: filename) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityLabel("Job photo \(filename)")
    }
}

struct ValidationMessages: View {
    let messages: [String]
    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(Set(messages)).sorted(), id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct BlankState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(detail)
        }
    }
}

// MARK: - Keyboard

extension UIApplication {
    /// Resigns whichever text field currently owns the keyboard.
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // Number and phone pads have no return key; give every text screen a way to close the keyboard.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.dismissKeyboard() }
                        .fontWeight(.semibold)
                }
            }
    }
}

extension View {
    /// Adds a "Done" button above the keyboard and lets a scroll gesture dismiss it.
    func keyboardDoneButton() -> some View { modifier(KeyboardDoneToolbar()) }
}

