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
        let rect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 45
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 0

            func text(_ value: String, x: CGFloat, width: CGFloat, size: CGFloat = 10,
                      bold: Bool = false, color: UIColor = .darkGray) -> CGFloat {
                let font = bold ? UIFont.systemFont(ofSize: size, weight: .semibold) : UIFont.systemFont(ofSize: size)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color
                ]
                let bounds = (value as NSString).boundingRect(
                    with: CGSize(width: width, height: 2000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
                )
                (value as NSString).draw(in: CGRect(x: x, y: y, width: width, height: max(18, bounds.height + 4)), withAttributes: attributes)
                return max(18, bounds.height + 4)
            }

            func footer() {
                let saved = y
                y = rect.height - 34
                _ = text("Page \(page)   •   \(quote.number)   •   Contractor-approved quotation",
                         x: margin, width: rect.width - margin * 2, size: 8, color: .gray)
                y = saved
            }

            func beginPage() {
                if page > 0 { footer() }
                context.beginPage()
                page += 1
                y = 45
                let blue = UIColor(red: 0.14, green: 0.35, blue: 0.96, alpha: 1)
                _ = text("TRADEQUOTE", x: margin, width: 330, size: 19, bold: true, color: blue)
                _ = text("QUOTATION", x: 430, width: 120, size: 13, bold: true)
                y += 35
                let nameHeight = text(business.name, x: margin, width: 340, size: 13, bold: true)
                y += nameHeight + 4
                let contact = [business.address, business.email, business.telephone, business.taxIdentifier]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                let contactHeight = text(contact, x: margin, width: 450)
                y += contactHeight + 16
                _ = text("Quote: \(quote.number)   •   \(quote.createdAt.formatted(date: .abbreviated, time: .omitted))",
                         x: margin, width: 470, bold: true)
                y += 28
                _ = text("Prepared for", x: margin, width: 250, size: 9)
                y += 17
                let customerHeight = text(customer.name, x: margin, width: 470, size: 12, bold: true)
                y += customerHeight + 1
                if !customer.address.isEmpty {
                    let addressHeight = text(customer.address, x: margin, width: 470)
                    y += addressHeight
                }
                y += 20
                _ = text("SCOPE", x: margin, width: 470, size: 10, bold: true)
                y += 21
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: y))
                line.addLine(to: CGPoint(x: rect.width - margin, y: y))
                UIColor.systemGray3.setStroke()
                line.stroke()
                y += 15
                _ = text("Description / specification", x: margin, width: 270, size: 9, bold: true)
                _ = text("Qty", x: 356, width: 37, size: 9, bold: true)
                _ = text("Rate", x: 410, width: 60, size: 9, bold: true)
                _ = text("Amount", x: 494, width: 70, size: 9, bold: true)
                y += 22
            }

            beginPage()
            let currency = quote.approvedCurrencyCode ?? business.currencyCode
            for kind in LineCategory.allCases {
                let group = quote.lines.filter { $0.category == kind }
                guard !group.isEmpty else { continue }
                if y > 690 { beginPage() }
                _ = text(kind.rawValue.uppercased(), x: margin, width: 220, size: 9, bold: true)
                y += 23
                for item in group {
                    guard let count = item.quantity, let rate = item.approvedUnitPrice else { continue }
                    if y > 705 { beginPage() }
                    let description = item.specification.isEmpty ? item.title : "\(item.title)\n\(item.specification)"
                    let lineHeight = text(description, x: margin, width: 290)
                    _ = text("\(count.editable) \(item.unit)", x: 349, width: 58)
                    _ = text(money(rate, currency), x: 406, width: 84)
                    _ = text(money(QuoteRules.roundMoney(rate * count), currency), x: 490, width: 85)
                    y += max(32, lineHeight + 10)
                }
                y += 12
            }
            if y > 625 { beginPage() }
            y += 15
            _ = text("Subtotal", x: 362, width: 125, bold: true)
            _ = text(money(amounts.subtotal, currency), x: 484, width: 95, bold: true)
            y += 23
            _ = text("VAT (\(vat.editable)%)", x: 362, width: 130)
            _ = text(money(amounts.vat, currency), x: 484, width: 95)
            y += 26
            _ = text("TOTAL", x: 362, width: 100, size: 14, bold: true)
            _ = text(money(amounts.total, currency), x: 460, width: 130, size: 14, bold: true)
            y += 49
            let terms = business.terms.trimmingCharacters(in: .whitespacesAndNewlines)
            if !terms.isEmpty {
                let termsHeight = (terms as NSString).boundingRect(
                    with: CGSize(width: 500, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.systemFont(ofSize: 10)], context: nil).height
                if y + 24 + termsHeight > rect.height - 50 { beginPage() }
                _ = text("TERMS", x: margin, width: 470, bold: true)
                y += 24
                _ = text(terms, x: margin, width: 500)
            }
            footer()
        }
    }

    static func money(_ decimal: Decimal, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: currency == "GBP" ? "en_GB" : "en_US")
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(decimal)"
    }
}
