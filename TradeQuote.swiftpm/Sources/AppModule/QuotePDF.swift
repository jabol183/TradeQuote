import UIKit
import Foundation
import QuoteCore

@MainActor
enum QuotePDF {
    enum Failure: LocalizedError {
        case incomplete
        var errorDescription: String? { "Quote is incomplete or pricing is not approved." }
    }
    static func generate(quote: Quote, business: BusinessProfile, customer: Customer, rates: [Rate]) throws -> Data {
        guard let vat = quote.approvedVATPercent,
              let amounts = QuoteRules.totals(quote, rates: rates, vatPercent: vat) else { throw Failure.incomplete }
        let business = quote.approvedBusiness ?? business
        let customer = quote.approvedCustomer ?? customer
        let currency = quote.approvedCurrencyCode ?? business.currencyCode
        let rect = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: rect).pdfData { context in
            var y: CGFloat = 0, page = 0
            func draw(_ value: String, x: CGFloat = 45, width: CGFloat = 505, size: CGFloat = 10, bold: Bool = false, color: UIColor = .darkGray) {
                var fontSize = size
                while fontSize > 6 && (value as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width > width { fontSize -= 0.5 }
                let font = UIFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
                (value as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 22), withAttributes: [.font: font, .foregroundColor: color])
            }
            func footer() {
                let position = y; y = 808
                draw("\(quote.number) · Page \(page) · Contractor-approved quotation", size: 8, color: .gray)
                y = position
            }
            func beginPage() {
                if page > 0 { footer() }
                context.beginPage(); page += 1; y = 38
                draw("TRADEQUOTE", size: 19, bold: true, color: UIColor(red: 0.14, green: 0.35, blue: 0.96, alpha: 1))
                draw("QUOTATION", x: 430, width: 120, size: 12, bold: true)
                y += 30
                draw(quote.number, size: 9, bold: true); y += 25
            }
            func space(_ height: CGFloat) { if y + height > 782 { beginPage() } }
            func lines(_ text: String, width: CGFloat, size: CGFloat) -> [String] {
                let font = UIFont.systemFont(ofSize: size)
                var result: [String] = []
                for paragraph in text.components(separatedBy: "\n") {
                    var current = ""
                    for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                        let candidate = current.isEmpty ? String(word) : current + " " + word
                        if (candidate as NSString).size(withAttributes: [.font: font]).width <= width { current = candidate }
                        else {
                            if !current.isEmpty { result.append(current); current = "" }
                            // Wrap long product IDs/URLs as well as ordinary words.
                            for character in word {
                                let next = current + String(character)
                                if (next as NSString).size(withAttributes: [.font: font]).width > width && !current.isEmpty { result.append(current); current = "" }
                                current.append(character)
                            }
                        }
                    }
                    result.append(current)
                }
                return result
            }
            func paragraph(_ text: String, size: CGFloat = 10, bold: Bool = false) {
                for line in lines(text, width: 505, size: size) {
                    space(size + 7); draw(line, size: size, bold: bold); y += size + 6
                }
                y += 5
            }
            beginPage()
            paragraph(business.name, size: 14, bold: true)
            paragraph([business.address, business.email, business.telephone, business.taxIdentifier].filter { !$0.isEmpty }.joined(separator: "\n"))
            paragraph("Prepared for \(customer.name)", size: 12, bold: true)
            if !customer.address.isEmpty { paragraph(customer.address) }
            paragraph("Created \(quote.createdAt.quoteDate) · \(quote.title)", bold: true)
            if let revision = quote.revisionOf { paragraph("Revision of \(revision)") }
            for category in LineCategory.allCases {
                let group = quote.lines.filter { $0.category == category }
                guard !group.isEmpty else { continue }
                space(45); paragraph(category.rawValue.uppercased(), bold: true)
                draw("Description / specification", width: 285, size: 8, bold: true)
                draw("Qty", x: 337, width: 60, size: 8, bold: true)
                draw("Rate", x: 405, width: 67, size: 8, bold: true)
                draw("Amount", x: 480, width: 70, size: 8, bold: true); y += 20
                for line in group {
                    guard let quantity = line.quantity, let price = line.approvedUnitPrice else { continue }
                    var description = line.title
                    if let room = line.room, !room.isEmpty { description += " [\(room)]" }
                    if line.disposition == .excluded { description = "EXCLUDED: " + description }
                    if line.disposition == .optional && line.optionalSelected != true { description = "OPTIONAL — not in total: " + description }
                    if !line.specification.isEmpty { description += "\n" + line.specification }
                    if line.supply == .customer { description += "\nCustomer supplies materials." }
                    let wrapped = lines(description, width: 280, size: 10)
                    for (index, text) in wrapped.enumerated() {
                        space(22); draw(text, width: 285)
                        if index == 0 {
                            draw("\(line.isApproximate == true ? "≈ " : "")\(quantity.editable) \(line.unit)", x: 337, width: 60, size: 9)
                            if WorkflowRules.isChargeable(line, in: quote) {
                                draw(money(price, currency), x: 405, width: 67, size: 9)
                                draw(money(QuoteRules.roundMoney(price * quantity), currency), x: 480, width: 70, size: 9)
                            } else {
                                let note = !WorkflowRules.included(line) ? "Not included" : (line.category == .materials ? "No purchase charge" : "Covered / allowance")
                                draw(note, x: 405, width: 145, size: 8)
                            }
                        }
                        y += 16
                    }
                    y += 10
                }
            }
            if quote.billingMethod == .fixed, let fixed = quote.fixedLabourPrice { paragraph("Agreed fixed labour total: \(money(fixed, currency))", bold: true) }
            space(95); y += 10
            draw("Subtotal: \(money(amounts.subtotal, currency))", x: 320, width: 230, bold: true); y += 24
            draw("VAT (\(vat.editable)%): \(money(amounts.vat, currency))", x: 320, width: 230); y += 24
            draw("TOTAL: \(money(amounts.total, currency))", x: 320, width: 230, size: 14, bold: true); y += 34
            paragraph("TERMS", bold: true)
            if let expiry = quote.expiresAt { paragraph("Valid until \(expiry.quoteDate).") }
            if let deposit = quote.depositPercent, deposit > 0 {
                paragraph("Deposit: \(deposit.editable)% (\(money(QuoteRules.roundMoney(amounts.total * deposit / 100), currency))).")
            }
            if let schedule = quote.paymentSchedule, !schedule.isEmpty { paragraph(schedule) }
            paragraph(quote.approvedTerms ?? business.terms)
            footer()
        }
    }
    static func money(_ decimal: Decimal, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency; formatter.currencyCode = currency
        formatter.locale = Locale(identifier: ["GBP": "en_GB", "PLN": "pl_PL", "EUR": "en_IE"][currency] ?? "en_US")
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(decimal)"
    }
}
