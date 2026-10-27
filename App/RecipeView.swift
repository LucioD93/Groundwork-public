import SwiftUI
import GroundsCore

struct RecipeView: View {
    @AppStorage("useOnDeviceAI") private var useOnDeviceAI = true
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let coffee: Coffee
    var fromScores = false
    @State private var method: BrewMethod = .espresso
    @State private var suggestion: BrewSuggestion?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var draft: Brew?
    @State private var savingRecipe = false
    @State private var adjustment = 0
    private var rated: [Brew] { RecipeGenerator.ratedBrews(store.brews, coffeeID: coffee.id, method: method) }
    private var recipe: Brew? {
        guard var brew = suggestion?.recipe else { return nil }
        if adjustment != 0, let setting = Double(brew.grindSetting) {
            brew.grindSetting = String(Int(min(180, max(20, setting.rounded() + Double(adjustment)))))
        }
        return brew
    }
    var body: some View {
        NavigationStack {
            JournalForm {
                Section {
                    Picker("Method", selection: $method) { ForEach(BrewMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).disabled(task != nil)
                    if fromScores {
                        Text("Based on \(rated.count) rated \(method.rawValue) \(rated.count == 1 ? "brew" : "brews"). Uses your saved records on this iPhone.")
                            .font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                        if rated.isEmpty { Text("Rate a cup of this coffee and method first.").font(.subheadline).foregroundStyle(JournalTheme.secondaryText) }
                    } else {
                        Label(useOnDeviceAI ? "On this iPhone" : "OpenAI · uses your API balance", systemImage: useOnDeviceAI ? "iphone" : "cloud")
                            .font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                        DisclosureGroup("About this starting recipe") {
                            Text("A label can suggest a starting point, but cannot measure taste or determine your grinder's clicks. Review the proposed dose and steps before using them.")
                                .font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                        }
                    }
                    if task != nil { ProgressView("Preparing a starting recipe…"); Button("Cancel generation") { task?.cancel(); task = nil }.journalAction() }
                    else if suggestion == nil { Button(fromScores ? "Find my reference recipe" : "Generate starting recipe") { generate() }.disabled(fromScores && rated.isEmpty).journalPrimary() }
                    if let error { InlineError(message: error) }
                }
                if let suggestion, let recipe {
                    Section(fromScores ? "Your reference recipe" : "Proposed starting recipe") {
                        Text(suggestion.summary).font(.subheadline)
                        Text(recipe.recipeSummary).font(.headline)
                        if let ratio = recipe.waterRatio { Text("Coffee to water · \(ratio)").font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
                        if let instructions = recipe.recipeNotes, !instructions.isEmpty { Text(instructions).textSelection(.enabled) }
                        if fromScores {
                            Picker("One optional experiment", selection: $adjustment) {
                                Text("Keep the recorded recipe").tag(0)
                                Text("Grind setting −1").tag(-1)
                                Text("Grind setting +1").tag(1)
                            }
                            Text("Use a single change to compare the next cup. Setting numbers only apply to the same grinder.").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                        }
                        Button("Use this recipe", systemImage: "cup.and.saucer") { draft = recipe.repeated() }.journalPrimary()
                        Button("Save recipe", systemImage: "bookmark") { savingRecipe = true }.journalAction()
                    }
                    if let evidence = suggestion.evidence.first {
                        Section("Recorded evidence") {
                            Text("\(suggestion.evidence.count) rated \(method.rawValue) \(suggestion.evidence.count == 1 ? "brew" : "brews"). Parameters come from the highest-rated cup; ties favor the latest.").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                            let reference = suggestion.evidence.sorted { $0.score == $1.score ? $0.date > $1.date : ($0.score ?? 0) > ($1.score ?? 0) }.first ?? evidence
                            LabeledContent("Recorded taste", value: reference.score.map { "\($0)/5" } ?? "Unknown")
                            LabeledContent("Recorded color", value: reference.colorRating.map { "\($0)/5" } ?? "Unknown")
                            LabeledContent("Recorded texture", value: reference.textureRating.map { "\($0)/5" } ?? "Unknown")
                            if method == .espresso { LabeledContent("Recorded flow", value: flowTitle(reference.flowRating)) }
                            if !reference.notes.isEmpty { Text(reference.notes).font(.subheadline) }
                        }
                    }
                    Section("Assumptions and limits") {
                        ForEach(Array(suggestion.assumptions.enumerated()), id: \.offset) { _, assumption in Text(assumption).font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
                    }
                    Section {
                        ShareLink(item: shareText) { Label("Share recipe", systemImage: "square.and.arrow.up") }.journalAction()
                        if !fromScores { Button("Generate another starting recipe") { generate() }.disabled(task != nil).journalAction() }
                    }
                }
            }.journalTitle(fromScores ? "Recipe from ratings" : "Photo recipe")
            .toolbar { Button("Done") { dismiss() }.journalAction() }
        }
        .onAppear {
            let available = fromScores ? store.brews.filter { $0.coffeeID == coffee.id && $0.score != nil } : store.brews.filter { $0.coffeeID == coffee.id }
            method = available.sorted { $0.date > $1.date }.first?.method ?? .espresso
            if fromScores { generate() }
        }
        .onChange(of: method) { _, _ in suggestion = nil; error = nil; adjustment = 0; if fromScores { generate() } }
        .onDisappear { task?.cancel(); task = nil }
        .sheet(item: $draft) { BrewEditor(brew: $0, previousFeedback: suggestion?.evidence.first?.notes) }
        .sheet(isPresented: $savingRecipe) { if let recipe { BrewEditor(brew: recipe.repeated(), savingRecipe: true) } }
    }
    private var shareText: String {
        guard let suggestion, let recipe else { return "" }
        return [coffee.name, recipe.method.rawValue, recipe.recipeSummary, recipe.recipeNotes ?? "", suggestion.summary, suggestion.assumptions.joined(separator: "\n")].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    private func generate() {
        error = nil; adjustment = 0
        if fromScores {
            do { suggestion = try BrewSuggestion.history(coffeeID: coffee.id, method: method, brews: store.brews) }
            catch { self.error = error.localizedDescription }
            return
        }
        task?.cancel()
        task = Task { @MainActor in
            defer { task = nil }
            do {
                let key = try aiKey(onDevice: useOnDeviceAI)
                guard let photo = coffee.photo, let root = store.journal?.photosDirectory,
                      let image = UIImage(contentsOfFile: root.appendingPathComponent(photo).path) else { throw JournalError.invalid("Choose a readable coffee label in Edit coffee first.") }
                let jpeg = try preparedCoffeePhoto(image)
                let plan: StartingRecipePlan
                if useOnDeviceAI { plan = try await OnDeviceAI.startingRecipe(coffee: coffee, method: method, label: try await readCoffeeLabel(jpeg)) }
                else { plan = try await RecipeGenerator().startingRecipe(coffee: coffee, method: method, jpeg: jpeg, apiKey: key) }
                try Task.checkCancellation()
                suggestion = try plan.suggestion(coffeeID: coffee.id, method: method, history: store.brews)
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
