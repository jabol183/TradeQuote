import Foundation

public enum RateCSV {
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
    public static func parse(_ text: String) throws -> [Rate] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if quoted || field.isEmpty { quoted.toggle() }
                else { throw Failure.invalid("Unexpected quote in CSV row \(rows.count + 1).") }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if c == "\n" && !quoted { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw Failure.invalid("An imported CSV field has an unclosed quote.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        rows = rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard let header = rows.first else { throw Failure.invalid("The CSV file is empty.") }
        let keys = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\u{feff}", with: "") }
        guard Set(keys).count == keys.count, ["name", "category", "unit", "amount"].allSatisfy(keys.contains) else {
            throw Failure.invalid("CSV needs unique name, category, unit and amount columns. Optional: aliases, productcode, purchasecost.")
        }
        return try rows.dropFirst().enumerated().map { offset, cells in
            guard cells.count == keys.count else { throw Failure.invalid("Wrong column count on CSV row \(offset + 2).") }
            let values = Dictionary(uniqueKeysWithValues: zip(keys, cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            let name = values["name"] ?? "", unit = QuoteRules.normalizedUnit(values["unit"] ?? "")
            guard !name.isEmpty, !unit.isEmpty, let category = LineCategory.allCases.first(where: { $0.rawValue.lowercased() == values["category"]?.lowercased() }) else {
                throw Failure.invalid("Check name, unit and category (Labour or Materials) on row \(offset + 2).")
            }
            let raw = values["amount"] ?? ""
            let amount = try decimal(raw, row: offset + 2)
            var rate = Rate(name: name, category: category, unit: unit, amount: amount)
            rate.aliases = values["aliases"]?.split(separator: "|").map(String.init)
            rate.productCode = values["productcode"]
            rate.purchaseCost = try decimal(values["purchasecost"] ?? "", row: offset + 2)
            rate.updatedAt = Date()
            return rate
        }
    }
    private static func decimal(_ text: String, row: Int) throws -> Decimal? {
        if text.isEmpty { return nil }
        guard text.range(of: "^[0-9]+([.,][0-9]{1,4})?$", options: .regularExpression) != nil,
              let value = Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")), value >= 0 else {
            throw Failure.invalid("Invalid non-negative price on row \(row). Use plain numbers without currency symbols.")
        }
        return value
    }
}
