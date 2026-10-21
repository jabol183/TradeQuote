import Foundation

public enum EvidenceRules {
    /// A generated quantity must have a literal numeric or spelled-out witness in its evidence.
    /// This is a guard, not proof that the quantity belongs to the correct object; review remains required.
    public static func supports(_ value: Decimal, in excerpt: String) -> Bool {
        let number = NSDecimalNumber(decimal: value)
        let escaped = NSRegularExpression.escapedPattern(for: number.stringValue).replacingOccurrences(of: "\\.", with: "[.,]")
        if excerpt.range(of: "(?<![0-9])" + escaped + "(?![0-9])", options: .regularExpression) != nil { return true }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.numberStyle = .spellOut
        if let spelled = formatter.string(from: number) {
            let pattern = " " + WorkflowRules.normalized(excerpt) + " "
            if pattern.contains(" " + WorkflowRules.normalized(spelled) + " ") { return true }
        }
        return false
    }
}
