import SwiftUI
import QuoteCore

struct RecipeLibraryView: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var choose: ((JobRecipe) -> Void)? = nil
    @State private var search = ""
    @State private var editing: JobRecipe?
    private var filtered: [JobRecipe] {
        search.isEmpty ? store.recipes : WorkflowRules.searchRecipes(search, recipes: store.recipes, limit: 100)
    }
    var body: some View {
        List {
            Section {
                Text("Your repeatable jobs. Set specifications, supply questions and optional components. Starter jobs contain no assumed prices or labour allowances.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(filtered) { recipe in
                HStack {
                    Button {
                        if let choose { choose(recipe); dismiss() } else { editing = recipe }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recipe.name).font(.headline)
                            Text("Per \(recipe.unit) · \(recipe.components.count) configured components").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button { editing = recipe } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Edit \(recipe.name)")
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Job recipes")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) { Button { editing = JobRecipe(name: "") } label: { Image(systemName: "plus") } }
        }
        .sheet(item: $editing) { recipe in RecipeEditor(recipe: recipe) }
    }
}
struct RecipeEditor: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var recipe: JobRecipe
    @State private var aliases = ""
    @State private var component: RecipeComponent?
    var body: some View {
        NavigationStack {
            Form {
                Section("Recognise this job") {
                    TextField("Job name", text: $recipe.name)
                    TextField("Phrases, separated by commas", text: $aliases, axis: .vertical)
                    TextField("Quantity unit", text: $recipe.unit)
                    TextField("Specification guidance (optional)", text: $recipe.specificationQuestion, axis: .vertical)
                    Toggle("Ask who supplies materials", isOn: $recipe.asksSupply)
                }
                Section("Standard wording to review for each job") {
                    TextField("Inclusions", text: $recipe.inclusions, axis: .vertical)
                    TextField("Exclusions", text: $recipe.exclusions, axis: .vertical)
                }
                Section("Contractor-configured components per job unit") {
                    ForEach(recipe.components) { item in
                        Button { component = item } label: {
                            Text("\(item.quantityPerJob.editable) \(item.unit) · \(item.title)")
                        }
                    }.onDelete { recipe.components.remove(atOffsets: $0) }
                    Button("Add labour or material component") {
                        component = RecipeComponent(title: "", category: .materials)
                    }
                    Text("Components are expanded only when you request it for a reviewed job. Customer-supplied material components are skipped. Review calculated quantities before approval.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Edit recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        recipe.aliases = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        store.updateRecipe(recipe); dismiss()
                    }.disabled(recipe.name.trimmingCharacters(in: .whitespaces).isEmpty || recipe.unit.isEmpty)
                }
            }
            .onAppear { aliases = recipe.aliases.joined(separator: ", ") }
            .sheet(item: $component) { item in
                RecipeComponentEditor(component: item) { saved in
                    if let i = recipe.components.firstIndex(where: { $0.id == saved.id }) { recipe.components[i] = saved }
                    else { recipe.components.append(saved) }
                }
            }
        }
    }
}
private struct RecipeComponentEditor: View {
    @Environment(TradeQuoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var component: RecipeComponent
    let save: (RecipeComponent) -> Void
    @State private var quantity = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $component.title)
                Picker("Category", selection: $component.category) { ForEach(LineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Units per job", text: $quantity).keyboardType(.decimalPad)
                TextField("Unit", text: $component.unit)
                Picker("Saved rate", selection: $component.rateID) {
                    Text("Select later").tag(nil as UUID?)
                    ForEach(store.rates.filter { $0.category == component.category && QuoteRules.unitsMatch($0.unit, component.unit) }) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Recipe component")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        component.quantityPerJob = quantity.asDecimal ?? 1
                        if !store.rates.contains(where: { $0.id == component.rateID && $0.category == component.category && QuoteRules.unitsMatch($0.unit, component.unit) }) { component.rateID = nil }
                        save(component); dismiss()
                    }.disabled(component.title.isEmpty || component.unit.isEmpty || (quantity.asDecimal ?? 0) <= 0)
                }
            }
            .onAppear { quantity = component.quantityPerJob.editable }
        }
    }
}
