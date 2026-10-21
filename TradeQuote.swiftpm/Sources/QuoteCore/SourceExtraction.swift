import Foundation

public enum SourceExtraction {
    public static func candidates(for item: ParsedWork, recipes: [JobRecipe]) -> [JobRecipe] {
        let object = " " + NoteParser.objectKey(item.object) + " "
        return WorkflowRules.searchRecipes(item.title, recipes: recipes, limit: recipes.count).filter { recipe in
            guard NoteParser.compatible(recipe, with: item) else { return false }
            if ["h", "day"].contains(item.unit) { return true }
            return ([recipe.name] + recipe.aliases).contains { phrase in
                var words = NoteParser.objectKey(phrase).split(separator: " ").map(String.init)
                if let first = words.first, ["replace", "install", "fit", "swap", "change", "allow", "existing"].contains(first) { words.removeFirst() }
                words.removeAll { $0 == "existing" }
                let key = words.joined(separator: " ")
                return !key.isEmpty && object.contains(" " + key + " ")
            }
        }
    }
    public static func line(from item: ParsedWork, source: EvidenceSource, recipe: JobRecipe? = nil) -> QuoteLine {
        let recipe = recipe.flatMap { NoteParser.compatible($0, with: item) ? $0 : nil }
        var line = QuoteLine(title: item.title, category: item.category, source: source,
            sourceDetail: item.excerpt, quantity: item.quantity, unit: item.unit)
        line.room = item.room
        line.sourceStart = item.sourceRange.location
        line.sourceLength = item.sourceRange.length
        line.disposition = item.disposition
        line.optionalSelected = false
        line.isApproximate = item.approximate
        line.supply = item.supply
        line.recipeID = recipe?.id
        line.capturedWorkObject = item.object
        line.workActionRequired = item.action.isEmpty
        if item.action.isEmpty {
            line.confirmationPrompt = "What work is needed? Choose an action or a job recipe."
            line.confirmationKind = .instruction
        }
        if let recipe {
            if !recipe.asksSupply && item.supply == .unknown { line.supply = MaterialSupply.none }
            if !recipe.specificationQuestion.isEmpty {
                line.confirmationPrompt = recipe.specificationQuestion
                line.confirmationKind = .specification
            }
        }
        return line
    }
    /// The same deterministic preparation used by production and the regression suite.
    public static func prepare(_ note: String, source: EvidenceSource, recipes: [JobRecipe]) -> (lines: [QuoteLine], warnings: [String]) {
        let parsed = NoteParser.parse(note)
        let lines = parsed.items.map { item in
            let candidates = candidates(for: item, recipes: recipes)
            return line(from: item, source: source, recipe: candidates.count == 1 ? candidates.first : nil)
        }
        return (lines, parsed.warnings)
    }
}
